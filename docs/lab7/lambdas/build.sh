#!/usr/bin/env bash
# Build Linux x86_64 Python 3.13 deployment ZIPs outside the repository.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-/tmp/opencode/timecapsule-lab7-build}"
mkdir -p "$out"
out="$(cd -- "$out" && pwd)"
for name in mailer opener; do
  stage="$(mktemp -d "$out/${name}.XXXXXX")"
  trap 'rm -rf "$stage"' EXIT
  python3 -m pip install --target "$stage" --platform manylinux2014_x86_64 \
    --python-version 3.13 --only-binary=:all: -r "$here/$name/requirements.txt"
  curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    -o "$stage/global-bundle.pem"
  cp "$here/$name/handler.py" "$stage/handler.py"
  rm -f "$out/$name.zip"
  (cd "$stage" && zip -qr "$out/$name.zip" .)
  rm -rf "$stage"
  trap - EXIT
  printf '%s\n' "$out/$name.zip"
done
