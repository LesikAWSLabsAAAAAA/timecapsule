#!/usr/bin/env bash
# Lab 5 cutover: provisioning, a verified PostgreSQL migration, and DNS.
set -Eeuo pipefail
umask 077

base=$(cd -- "$(dirname -- "$0")" && pwd)
stack=$base/part2-app
mode=${1:?Usage: run-part2.sh provision|migrate|cutover|smoke|all PRIVATE_LOG_DIR}
log=${2:?Supply a private log directory outside the repository}
mkdir -p -- "$log"
log=$(cd -- "$log" && pwd)
[[ $(stat -c '%a' "$log") == 700 ]] || { echo 'Log directory must have mode 0700.' >&2; exit 1; }
tofu_app() { tofu -chdir="$stack" "$@"; }

plan_actions() {
    tofu_app show -json "$1" | python3 -c '
import json, sys
p = json.load(sys.stdin)
for item in p.get("resource_changes", []):
    actions = item["change"]["actions"]
    if item["mode"] == "managed" and actions != ["no-op"]:
        print(item["address"], ",".join(actions))
'
}

provision() {
    tofu_app plan -input=false -no-color -var=switch_database_dns=false \
        -out="$log/provision.tfplan" > "$log/provision-plan.txt" 2>&1
    local actions line
    actions=$(plan_actions "$log/provision.tfplan")
    while IFS= read -r line; do
        case "$line" in
            ""|"aws_db_instance.app create"|"aws_db_subnet_group.app create"|\
            "aws_security_group.rds create"|"aws_iam_policy.rds_stop create"|\
            "aws_iam_role.scheduler create"|"aws_iam_role_policy_attachment.rds_stop create"|\
            "aws_scheduler_schedule.nightly_stop create") ;;
            *) echo "Unexpected provisioning action: $line" >&2; return 1 ;;
        esac
    done <<< "$actions"
    tofu_app apply -input=false -no-color "$log/provision.tfplan" > "$log/provision-apply.txt" 2>&1
}

endpoint() {
    local h
    h=$(tofu_app output -raw db_address)
    [[ $h =~ ^timecapsule-dev-rds\.[a-zA-Z0-9.-]+\.rds\.amazonaws\.com$ ]] || return 1
    printf '%s\n' "$h"
}

migrate() {
    local h
    h=$(endpoint)
    test ! -e "$log/migration-complete"
    {
        # Start the remote script with a password read from stdin, never argv.
        if [[ -n ${TF_VAR_db_admin_password:-} ]]; then
            printf '%s\n' "$TF_VAR_db_admin_password"
        else
            sed -n 's/^db_admin_password[[:space:]]*=[[:space:]]*"\([[:alnum:]]*\)"$/\1/p' "$stack/terraform.tfvars"
        fi
        cat <<'REMOTE'
set -Eeuo pipefail
trap 'printf "Remote migration stopped at line %s (status %s).\n" "$LINENO" "$?" >&2' ERR
umask 077
cd /var/www/timecapsule
app_password=$(php -r 'ob_start(); require "src/bootstrap.php"; ob_end_clean(); echo config("DB_PASSWORD", "");')
test -n "$app_password" || { echo 'Application database credential is missing.' >&2; exit 1; }
app_db_host=$(php -r 'ob_start(); require "src/bootstrap.php"; ob_end_clean(); echo config("DB_HOST", "");')
test "$app_db_host" = db.timecapsule.internal || { echo 'Unexpected configured DB_HOST.' >&2; exit 1; }
source_ip=$(getent ahostsv4 db.timecapsule.internal | awk 'NR==1{print $1}')
[[ $source_ip == 10.18.11.157 ]] || { echo 'Legacy DNS does not resolve to the expected source.' >&2; exit 1; }
[[ $RDS == timecapsule-dev-rds.*.rds.amazonaws.com ]] || { echo 'Unexpected RDS endpoint.' >&2; exit 1; }
tmp=$(mktemp -d /run/lab5-migrate.XXXXXXXX)
paused=0
complete=0
cleanup() {
    rm -rf -- "$tmp"
    if (( paused && ! complete )); then systemctl start nginx; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

old() { PGPASSWORD="$app_password" PGSSLMODE=prefer PGCONNECT_TIMEOUT=5 psql -Xw -v ON_ERROR_STOP=1 -h db.timecapsule.internal -U timecapsule -d timecapsule "$@"; }
new() { PGPASSWORD="$app_password" PGSSLMODE=require PGCONNECT_TIMEOUT=5 psql -Xw -v ON_ERROR_STOP=1 -h "$RDS" -U timecapsule -d timecapsule "$@"; }
admin() { PGPASSWORD="$ADMIN_PASSWORD" PGSSLMODE=require PGCONNECT_TIMEOUT=5 psql -Xw -v ON_ERROR_STOP=1 -h "$RDS" -U dbadmin -d postgres "$@"; }

old -Atc "SELECT current_database(), current_user, version()"
admin -Atc "SELECT current_database(), current_user, version()"
if [[ $(admin -Atc "SELECT count(*) FROM pg_roles WHERE rolname='timecapsule'") == 0 ]]; then
    admin -c 'CREATE ROLE timecapsule LOGIN;'
fi
printf '%s\n%s\n' "$app_password" "$app_password" | admin -c '\password timecapsule'
admin -c 'GRANT timecapsule TO dbadmin;'
if [[ $(admin -Atc "SELECT count(*) FROM pg_database WHERE datname='timecapsule'") == 0 ]]; then
    admin -c 'CREATE DATABASE timecapsule OWNER timecapsule;'
fi
[[ $(new -Atc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','S');") == 0 ]]
new -c '\conninfo'

systemctl is-active --quiet nginx
paused=1
systemctl stop nginx
if systemctl is-active --quiet nginx; then exit 1; fi
printf '%s\n' 'Nginx stopped: no requests can write to the source during the dump.'
for attempt in {1..12}; do
    other_sessions=$(old -Atc "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND usename=current_user AND pid<>pg_backend_pid();")
    [[ $other_sessions == 0 ]] && break
    sleep 2
done
[[ $other_sessions == 0 ]]

PGPASSWORD="$app_password" PGSSLMODE=prefer PGCONNECT_TIMEOUT=5 pg_dump \
    -w -h db.timecapsule.internal -U timecapsule -d timecapsule \
    --format=custom --no-owner --no-privileges -f "$tmp/db.dump"
PGPASSWORD="$app_password" PGSSLMODE=require PGCONNECT_TIMEOUT=5 pg_restore \
    -w -h "$RDS" -U timecapsule -d timecapsule --no-owner --no-privileges \
    --single-transaction --exit-on-error "$tmp/db.dump"

printf 'table          source   RDS      matching contents\n'
for table in users capsules notifications; do
    left=$(old -Atc "SELECT count(*) FROM $table")
    right=$(new -Atc "SELECT count(*) FROM $table")
    old_hash=$(old -c "COPY (SELECT * FROM $table ORDER BY id) TO STDOUT" | sha256sum)
    new_hash=$(new -c "COPY (SELECT * FROM $table ORDER BY id) TO STDOUT" | sha256sum)
    [[ $left == "$right" && $old_hash == "$new_hash" ]]
    printf '%-14s %-8s %-8s yes\n' "$table" "$left" "$right"
done
complete=1
printf '%s\n' 'Verified. The private dump will be removed; Nginx stays stopped until DNS verification.'
REMOTE
    } | ssh -o BatchMode=yes app "sudo -n bash -c 'IFS= read -r ADMIN_PASSWORD; test -n \"\$ADMIN_PASSWORD\" || exit 1; export ADMIN_PASSWORD; export RDS=$h; exec bash -s'" \
        > "$log/migration.txt" 2>&1
    printf '%s\n' "$h" > "$log/migration-complete"
}

cutover() {
    local h actions
    h=$(endpoint)
    test "$(cat "$log/migration-complete")" = "$h"
    ssh -o BatchMode=yes app '! systemctl is-active --quiet nginx'
    tofu_app plan -input=false -no-color -var=switch_database_dns=true \
        -out="$log/cutover.tfplan" > "$log/cutover-plan.txt" 2>&1
    actions=$(plan_actions "$log/cutover.tfplan")
    [[ $actions == 'aws_route53_record.db update' || -z $actions ]] || {
        echo "Unexpected cutover action: $actions" >&2; return 1;
    }
    if [[ -n $actions ]]; then
        tofu_app apply -input=false -no-color "$log/cutover.tfplan" > "$log/cutover-apply.txt" 2>&1
    fi
    printf 'switch_database_dns = true\n' > "$stack/cutover.auto.tfvars"

    ssh -o BatchMode=yes app "sudo -n env RDS=$h bash -s" > "$log/dns-health.txt" 2>&1 <<'REMOTE'
set -euo pipefail
cd /var/www/timecapsule
for attempt in {1..70}; do
    cname=$(dig +time=2 +tries=1 +short db.timecapsule.internal CNAME || :)
    expected_ip=$(getent ahostsv4 "$RDS" | awk 'NR==1{print $1}' || :)
    app_ip=$(getent ahostsv4 db.timecapsule.internal | awk 'NR==1{print $1}' || :)
    [[ "${cname%.}" == "$RDS" && -n "$expected_ip" && "$app_ip" == "$expected_ip" ]] && break
    sleep 5
done
[[ "${cname%.}" == "$RDS" && -n "$expected_ip" && "$app_ip" == "$expected_ip" ]]
dig +noall +answer db.timecapsule.internal
export EXPECTED_IP=$expected_ip
php <<'PHP'
<?php
require 'src/bootstrap.php';
$row = db()->query(
    "SELECT host(inet_server_addr()) AS server_ip, " .
    "(SELECT ssl::text FROM pg_stat_ssl WHERE pid=pg_backend_pid()) AS tls"
)->fetch();
if ($row['server_ip'] !== getenv('EXPECTED_IP') || $row['tls'] !== 'true') {
    fwrite(STDERR, "PHP has not verified the RDS endpoint and TLS; leaving Nginx stopped.\n");
    exit(1);
}
echo "PHP PDO connected to the verified RDS address over TLS.\n";
PHP
systemctl start nginx
curl --fail --silent --show-error --max-time 15 --write-out '\nHTTP %{http_code}\n' http://127.0.0.1/health
REMOTE
}

smoke() {
    local h
    h=$(endpoint)
    test "$(cat "$log/migration-complete")" = "$h"
    ssh -o BatchMode=yes app "sudo -n env RDS=$h bash -s" > "$log/smoke.txt" 2>&1 <<'REMOTE'
set -euo pipefail
cd /var/www/timecapsule
cname=$(dig +time=2 +tries=1 +short db.timecapsule.internal CNAME)
[[ "${cname%.}" == "$RDS" ]]
expected_ip=$(getent ahostsv4 "$RDS" | awk 'NR==1{print $1}')
test -n "$expected_ip"
export EXPECTED_IP=$expected_ip
token=$(python3 -c 'import secrets; print(secrets.token_hex(6))')
title="Lab5 RDS smoke $token"
capsule_id=$(python3 - "$token" "$title" <<'PY'
import datetime
import http.cookiejar
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

base = "http://127.0.0.1"
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
token, title = sys.argv[1:]

def form(path):
    with client.open(base + path, timeout=10) as response:
        match = re.search(rb'name="_token" value="([a-f0-9]+)"', response.read())
    if not match:
        raise RuntimeError(f"CSRF field not found on {path}")
    return match[1].decode()

def post(path, **fields):
    data = urllib.parse.urlencode(fields).encode()
    with client.open(base + path, data=data, timeout=15) as response:
        return urllib.parse.urlparse(response.url).path

try:
    register_token = form("/register")
except urllib.error.HTTPError as exc:
    if exc.code != 404:
        raise
else:
    password = secrets.token_urlsafe(24)
    assert post("/register", _token=register_token, email=f"lab5-{token}@example.invalid",
                password=password, password_confirmation=password) == "/"

date = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)
path = post("/capsules", _token=form("/capsules/new"), title=title, message="Lab 5 RDS smoke test.",
            open_at=date.strftime("%Y-%m-%dT%H:%M"),
            open_at_utc=date.isoformat(timespec="milliseconds").replace("+00:00", "Z"))
match = re.fullmatch(r"/capsules/(\d+)", path)
if not match:
    raise RuntimeError(f"Expected capsule redirect, got {path}")
print(match[1])
PY
)
export CAPSULE_ID=$capsule_id CAPSULE_TITLE=$title
printf 'HTTP POST /capsules redirected to /capsules/%s\n' "$capsule_id"
php <<'PHP'
<?php
require 'src/bootstrap.php';
$row = db_query(
    "SELECT id, title, host(inet_server_addr()) AS server_ip, " .
    "(SELECT ssl::text FROM pg_stat_ssl WHERE pid=pg_backend_pid()) AS tls " .
    "FROM capsules WHERE id = ? AND title = ?",
    [getenv('CAPSULE_ID'), getenv('CAPSULE_TITLE')]
)->fetch();
if (!$row || $row['tls'] !== 'true' || $row['server_ip'] !== getenv('EXPECTED_IP')) {
    fwrite(STDERR, "Test capsule not found over TLS.\n");
    exit(1);
}
echo json_encode($row, JSON_THROW_ON_ERROR) . "\n";
PHP
REMOTE
}

case "$mode" in
    provision) provision ;;
    migrate) migrate ;;
    cutover) cutover ;;
    smoke) smoke ;;
    all) provision; migrate; cutover; smoke ;;
    *) echo "Unknown action: $mode" >&2; exit 2 ;;
esac
