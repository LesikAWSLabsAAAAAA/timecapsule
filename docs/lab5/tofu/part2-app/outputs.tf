output "db_instance_id" {
  description = "RDS identifier."
  value       = aws_db_instance.app.identifier
}

output "db_endpoint" {
  description = "RDS endpoint in host:port form."
  value       = aws_db_instance.app.endpoint
}

output "db_address" {
  description = "RDS hostname (without the port)."
  value       = aws_db_instance.app.address
}

output "db_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.app.port
}

output "db_engine_version_actual" {
  description = "PostgreSQL version reported by RDS."
  value       = aws_db_instance.app.engine_version_actual
}

output "db_instance_arn" {
  description = "ARN used by the scheduler policy."
  value       = aws_db_instance.app.arn
}

output "rds_security_group_id" {
  description = "Security group attached to RDS."
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group used by RDS."
  value       = aws_db_subnet_group.app.name
}

output "stop_schedule_name" {
  description = "EventBridge Scheduler schedule that stops the database."
  value       = aws_scheduler_schedule.nightly_stop.name
}

output "scheduler_role_arn" {
  description = "IAM role assumed by EventBridge Scheduler."
  value       = aws_iam_role.scheduler.arn
}

output "database_dns_name" {
  description = "Stable application DNS name."
  value       = aws_route53_record.db.fqdn
}
