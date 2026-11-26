variable "region" {
  description = "AWS region for every resource of the lab."
  type        = string
  default     = "eu-central-1"
}

variable "db_admin_password" {
  description = "Master password for the dbadmin user. Keep it in terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "engine_version" {
  description = "PostgreSQL major version. The lab expects the 16 branch."
  type        = string
  default     = "16"
}

variable "backup_retention_days" {
  description = "Use 1 day on the AWS Free account plan; set 7 only on an account that supports it."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 7], var.backup_retention_days)
    error_message = "Choose 1 day for the Free plan or 7 days for the original lab."
  }
}

variable "stop_schedule_expression" {
  description = "EventBridge Scheduler cron expression for the nightly stop (Europe/Chisinau)."
  type        = string
  default     = "cron(0 23 * * ? *)"
}

# Task 9 (pg_dump) must still reach db-server through db.timecapsule.internal.
# Switch explicitly only after the data is loaded and verified on RDS.
variable "switch_database_dns" {
  description = "Point db.timecapsule.internal to RDS instead of the legacy db-server."
  type        = bool
  default     = false
}

variable "legacy_db_ip" {
  description = "Address of db-server used while switch_database_dns = false."
  type        = string
  default     = "10.18.11.157"
}

variable "tags" {
  description = "Common tags for the lab."
  type        = map(string)
  default = {
    Lab = "lab5"
  }
}
