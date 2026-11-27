<?php
// Database connection. Host, port, database and user come from the environment;
// the password comes from Secrets Manager (DB_SECRET_ARN) or, for local
// development only, from DB_PASSWORD.

function db(): PDO
{
    static $pdo = null; // one connection per request, created on first use

    if ($pdo === null) {
        $dsn = sprintf(
            'pgsql:host=%s;port=%s;dbname=%s',
            config('DB_HOST', 'localhost'),
            config('DB_PORT', '5432'),
            config('DB_NAME', 'timecapsule')
        );

        $pdo = new PDO($dsn, config('DB_USER', 'timecapsule'), db_password(), [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,        // SQL errors throw exceptions
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,   // rows as ['column' => value]
            PDO::ATTR_TIMEOUT => 5,                             // fail fast if the DB is down
        ]);

        // Columns are TIMESTAMP without time zone and always hold UTC values.
        $pdo->exec("SET TIME ZONE 'UTC'");
    }

    return $pdo;
}

// Run a query with parameters and return the statement.
function db_query(string $sql, array $params = []): PDOStatement
{
    $statement = db()->prepare($sql);
    $statement->execute($params);
    return $statement;
}

// True when the exception came from the Secrets Manager credential lookup,
// not from PostgreSQL itself.
function db_error_is_secret(Throwable $e): bool
{
    $message = $e->getMessage();
    return str_contains($message, 'Secrets Manager') || str_contains($message, 'database secret');
}

// Turn common database errors into a short hint for the person running the app.
// Returns null for any other error.
function db_problem_hint(Throwable $e): ?string
{
    if (db_error_is_secret($e)) {
        return 'Cannot load database credentials from Secrets Manager. Check DB_SECRET_ARN and the timecapsule-dev-app-secretsmanager policy.';
    }

    $message = $e->getMessage();
    if (!$e instanceof PDOException) {
        return null;
    }

    if (str_contains($message, 'SQLSTATE[42P01]')) {       // undefined table
        return 'The database has no tables yet. Run: php bin/init-db.php';
    }
    if (str_contains($message, 'SQLSTATE[08')) {           // connection errors (08xxx)
        return 'Cannot connect to the database. Check DB_HOST, DB_PORT, DB_NAME, DB_USER and the database password (DB_SECRET_ARN or DB_PASSWORD).';
    }
    return null;
}

// Current time as a string for SQL, e.g. "2026-09-17 14:05:00" (UTC).
function now_utc(): string
{
    return gmdate('Y-m-d H:i:s');
}
