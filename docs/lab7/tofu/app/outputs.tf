output "topic_arn" {
  value = aws_sns_topic.events.arn
}

output "mail_queue_url" {
  value = aws_sqs_queue.mail.id
}

output "mail_queue_arn" {
  value = aws_sqs_queue.mail.arn
}

output "mail_dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "mailer_function_arn" {
  value = aws_lambda_function.app["mailer"].arn
}

output "opener_function_arn" {
  value = aws_lambda_function.app["opener"].arn
}

output "mail_event_source_mapping_uuid" {
  value = aws_lambda_event_source_mapping.mail.uuid
}

output "scheduler_name" {
  value = aws_scheduler_schedule.opener.name
}
