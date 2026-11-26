output "sandbox_endpoint" {
  description = "lab5-db endpoint (host:port)."
  value       = aws_db_instance.sandbox.endpoint
}

output "sandbox_address" {
  description = "lab5-db hostname."
  value       = aws_db_instance.sandbox.address
}

output "sandbox_engine_version_actual" {
  description = "PostgreSQL version reported by RDS."
  value       = aws_db_instance.sandbox.engine_version_actual
}

output "client_instance_id" {
  description = "Existing app-server that receives lab5-web-sg."
  value       = data.aws_instance.client.id
}

output "replica_endpoint" {
  description = "lab5-db-replica endpoint, empty when the replica is disabled."
  value       = try(aws_db_instance.replica[0].endpoint, "")
}

output "restore_endpoint" {
  description = "lab5-db-restore endpoint, empty when the restore is disabled."
  value       = try(aws_db_instance.restore[0].endpoint, "")
}
