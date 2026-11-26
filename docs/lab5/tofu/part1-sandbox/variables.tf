variable "region" {
  description = "AWS region for every resource of the lab."
  type        = string
  default     = "eu-central-1"
}

variable "db_admin_password" {
  description = "Master password for dbadmin on lab5-db. Keep it in terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "enable_deletion_protection" {
  description = "Task 2 requires deletion protection. Set to false right before the final destroy."
  type        = bool
  default     = true
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

# Task 4 creates the read replica and task 5 deletes it. Toggle the replica off
# before creating the point-in-time restore.
variable "create_replica" {
  description = "Create lab5-db-replica."
  type        = bool
  default     = false
}

# Task 5 restores lab5-db to the moment before DELETE FROM notes.
variable "create_restore" {
  description = "Create lab5-db-restore from a point in time."
  type        = bool
  default     = false
}

variable "restore_time" {
  description = "UTC timestamp in RFC3339, e.g. 2026-11-26T19:05:00Z. Required when create_restore = true."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags for the lab."
  type        = map(string)
  default = {
    Lab = "lab5"
  }
}
