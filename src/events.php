<?php
// Publish only the identifier: the worker retrieves notification data from RDS.
function publish_capsule_sealed(int $capsuleId): void
{
    $topic = config('EVENTS_TOPIC_ARN');
    if (!$topic) {
        throw new RuntimeException('EVENTS_TOPIC_ARN must be configured for asynchronous notifications.');
    }
    $sns = new Aws\Sns\SnsClient([
        'version' => 'latest',
        'region' => config('AWS_REGION', 'eu-central-1'),
    ]);
    $sns->publish([
        'TopicArn' => $topic,
        'Message' => json_encode(
            ['eventType' => 'capsule.sealed', 'capsuleId' => $capsuleId],
            JSON_THROW_ON_ERROR
        ),
    ]);
}
