<?php
// Database credentials from AWS Secrets Manager.
//
// When DB_SECRET_ARN is set, the application asks Secrets Manager for the
// password and caches it for a short time in memory (tmpfs by default). The
// password is never written to .env, baked into an AMI, or logged.
//
// Local development and docker-compose can keep using DB_PASSWORD.

use Aws\Exception\AwsException;
use Aws\SecretsManager\SecretsManagerClient;

// ARN of the secret that contains {"password":"..."}; null when the app uses
// the local DB_PASSWORD fallback.
function db_secret_arn(): ?string
{
    return config('DB_SECRET_ARN');
}

// The password for the application database user. Secrets Manager is the
// preferred source; DB_PASSWORD remains only for local development.
function db_password(): string
{
    $arn = db_secret_arn();
    if ($arn === null) {
        return config('DB_PASSWORD', 'secret');
    }

    $cached = secret_cache_read($arn);
    if ($cached !== null) {
        return $cached;
    }

    $password = secret_fetch_password($arn);
    secret_cache_write($arn, $password);

    return $password;
}

// Call Secrets Manager once. The SDK uses the EC2 instance role through the
// default credential provider chain; no access keys are configured here.
function secret_fetch_password(string $arn): string
{
    $timeout = max(1, config_int('SECRET_FETCH_TIMEOUT_SECONDS', 2));
    $client = new SecretsManagerClient([
        'version' => 'latest',
        'region' => config('AWS_REGION', 'eu-central-1'),
        'http' => [
            'timeout' => $timeout,
            'connect_timeout' => min(1, $timeout),
        ],
        // One retry keeps a broken policy fail-fast; the default retries hide
        // the dependency problem for too long.
        'retries' => 1,
    ]);

    try {
        $result = $client->getSecretValue(['SecretId' => $arn]);
    } catch (Throwable $e) {
        $code = $e instanceof AwsException ? (string) $e->getAwsErrorCode() : get_class($e);
        error_log('Secrets Manager GetSecretValue failed: ' . $code);
        throw new RuntimeException('Cannot load database credentials from Secrets Manager.', 0, $e);
    }

    $payload = $result['SecretString'] ?? null;
    if (!is_string($payload) || $payload === '') {
        throw new RuntimeException('The database secret has no SecretString.');
    }

    $data = json_decode($payload, true);
    if (
        !is_array($data)
        || !isset($data['password'])
        || !is_string($data['password'])
        || $data['password'] === ''
    ) {
        throw new RuntimeException('The database secret does not contain a password.');
    }

    return $data['password'];
}

// Cache file path, or null when caching is disabled or unavailable.
// /dev/shm is memory-backed, so the password is not written to an EBS volume.
function secret_cache_path(string $arn): ?string
{
    $ttl = config_int('SECRET_CACHE_TTL_SECONDS', 300);
    if ($ttl <= 0) {
        return null;
    }

    $dir = rtrim((string) config('SECRET_CACHE_DIR', '/dev/shm'), '/');
    if (!is_dir($dir) || !is_writable($dir)) {
        $dir = ROOT_DIR . '/storage/cache';
    }
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    if (!is_dir($dir) || !is_writable($dir)) {
        return null;
    }

    return $dir . '/timecapsule-db-' . hash('sha256', $arn) . '.json';
}

function secret_cache_read(string $arn): ?string
{
    $path = secret_cache_path($arn);
    if ($path === null || !is_file($path)) {
        return null;
    }

    $raw = @file_get_contents($path);
    if ($raw === false) {
        return null;
    }

    $data = json_decode($raw, true);
    if (
        !is_array($data)
        || !isset($data['expires_at'], $data['password'])
        || !is_string($data['password'])
    ) {
        @unlink($path);
        return null;
    }

    if ((int) $data['expires_at'] <= time()) {
        @unlink($path);
        return null;
    }

    return $data['password'];
}

function secret_cache_write(string $arn, string $password): void
{
    $path = secret_cache_path($arn);
    if ($path === null) {
        return;
    }

    $ttl = max(1, config_int('SECRET_CACHE_TTL_SECONDS', 300));
    try {
        $payload = json_encode(
            ['expires_at' => time() + $ttl, 'password' => $password],
            JSON_THROW_ON_ERROR
        );
    } catch (JsonException) {
        return;
    }

    // Write to a temporary file first and rename it, so another request never
    // reads a half-written secret.
    $temporary = $path . '.' . bin2hex(random_bytes(4));
    if (@file_put_contents($temporary, $payload, LOCK_EX) === false) {
        return;
    }
    @chmod($temporary, 0600);
    if (!@rename($temporary, $path)) {
        @unlink($temporary);
        return;
    }
    @chmod($path, 0600);
}
