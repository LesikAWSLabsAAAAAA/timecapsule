<?php
// File storage for capsule attachments.
// All files are stored in Amazon S3 under the "uploads/" prefix.

use Aws\S3\S3Client;

// Create S3 client only once.
function storage_s3(): S3Client
{
    static $s3 = null;

    if ($s3 === null) {
        $s3 = new S3Client([
            'version' => 'latest',
            'region'  => config('AWS_REGION', 'eu-central-1'),
        ]);
    }

    return $s3;
}

// Get bucket name from .env.
function storage_bucket(): string
{
    $bucket = config('S3_BUCKET');

    if (empty($bucket)) {
        throw new RuntimeException('S3_BUCKET is not configured.');
    }

    return $bucket;
}

// Save uploaded file to S3 and return its random stored name.
function storage_save(array $uploadedFile, string $extension): string
{
    if (
        !isset($uploadedFile['tmp_name']) ||
        !is_uploaded_file($uploadedFile['tmp_name'])
    ) {
        throw new RuntimeException('Invalid uploaded file.');
    }

    if (
        isset($uploadedFile['error']) &&
        $uploadedFile['error'] !== UPLOAD_ERR_OK
    ) {
        throw new RuntimeException('Upload failed.');
    }

    $extension = preg_replace('/[^A-Za-z0-9]/', '', $extension);

    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;

    $mime = mime_content_type($uploadedFile['tmp_name'])
        ?: 'application/octet-stream';

    storage_s3()->putObject([
        'Bucket'      => storage_bucket(),
        'Key'         => 'uploads/' . $storedName,
        'SourceFile'  => $uploadedFile['tmp_name'],
        'ContentType' => $mime,
    ]);

    return $storedName;
}

// Delete an object from S3.
function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    storage_s3()->deleteObject([
        'Bucket' => storage_bucket(),
        'Key'    => 'uploads/' . basename($storedName),
    ]);
}

// Redirect browser to a presigned S3 URL valid for 5 minutes.
function storage_stream(
    string $storedName,
    string $mime,
    string $downloadName,
    string $disposition
): void {
    if (!in_array($disposition, ['inline', 'attachment'], true)) {
        $disposition = 'attachment';
    }

    $asciiName = preg_replace(
        '/[^A-Za-z0-9._ -]/',
        '_',
        $downloadName
    );

    $contentDisposition = sprintf(
        '%s; filename="%s"; filename*=UTF-8\'\'%s',
        $disposition,
        $asciiName,
        rawurlencode($downloadName)
    );

    $command = storage_s3()->getCommand('GetObject', [
        'Bucket' => storage_bucket(),
        'Key'    => 'uploads/' . basename($storedName),
        'ResponseContentType' => $mime,
        'ResponseContentDisposition' => $contentDisposition,
    ]);

    $request = storage_s3()->createPresignedRequest(
        $command,
        '+5 minutes'
    );

    header('X-Content-Type-Options: nosniff');
    header('Location: ' . (string) $request->getUri(), true, 302);
    exit;
}
