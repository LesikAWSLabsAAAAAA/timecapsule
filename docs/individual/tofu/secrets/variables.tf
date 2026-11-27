variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "secret_name" {
  type        = string
  description = "Secrets Manager secret name."
  default     = "timecapsule-dev-db"
}

variable "db_instance_identifier" {
  type        = string
  description = "Existing RDS instance (read through a data source)."
  default     = "timecapsule-dev-rds"
}

variable "db_name" {
  type    = string
  default = "timecapsule"
}

variable "db_user" {
  type    = string
  default = "timecapsule"
}

variable "db_password" {
  type        = string
  description = "Application database password; pass it through TF_VAR_db_password, never commit it."
  sensitive   = true
}

variable "app_role_name" {
  type        = string
  description = "Existing EC2 instance role used by the application."
  default     = "timecapsule-dev-app-role"
}

variable "enable_secret_access" {
  type        = bool
  description = "Allow the app role to read the secret. Set false only for the B4 failure exercise."
  default     = true
}
