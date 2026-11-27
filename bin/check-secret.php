<?php
// Check the database credential source without printing the password.
//
//   php bin/check-secret.php
//
// Exit code 0 means both the secret (when configured) and a real database
// query work. The script is useful before creating an AMI and during the B4
// failure exercise.

require dirname(__DIR__) . '/src/bootstrap.php';

$arn = db_secret_arn();
echo 'source: ' . ($arn !== null ? 'secretsmanager' : 'env') . "\n";
if ($arn !== null) {
    // Do not print the AWS account id into evidence screenshots.
    echo 'secret_arn: ' . preg_replace('/\d{12}/', '<account>', $arn) . "\n";
    echo 'cache_ttl_seconds: ' . config_int('SECRET_CACHE_TTL_SECONDS', 300) . "\n";
}

try {
    $started = microtime(true);
    $password = db_password();
    $elapsed = (int) round((microtime(true) - $started) * 1000);

    echo 'credentials: ok (' . strlen($password) . " chars, {$elapsed} ms)\n";

    db()->query('SELECT 1');
    echo "database: ok\n";
    exit(0);
} catch (Throwable $e) {
    fwrite(STDERR, 'FAILED: ' . $e->getMessage() . "\n");
    if (config_bool('APP_DEBUG')) {
        fwrite(STDERR, (string) $e . "\n");
    }
    exit(1);
}
