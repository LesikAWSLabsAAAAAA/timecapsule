variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "mailer_zip" {
  type        = string
  description = "Path to externally built mailer zip with dependencies and RDS CA bundle."
}

variable "opener_zip" {
  type        = string
  description = "Path to externally built opener zip with dependencies and RDS CA bundle."
}

variable "db_user" {
  type        = string
  description = "Existing least-privilege PostgreSQL user."
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type    = string
  default = "timecapsule"
}

variable "db_sslrootcert" {
  type        = string
  description = "Path inside each deployed Lambda package to the RDS CA bundle."
  default     = "/var/task/global-bundle.pem"
}

variable "email" {
  type      = string
  sensitive = true
}

variable "enable_mail_trigger" {
  type    = bool
  default = false
}

variable "enable_scheduler" {
  type    = bool
  default = false
}

variable "simulate_mail_failure" {
  description = "Temporarily use an incorrect mailer database password for the DLQ exercise."
  type        = bool
  default     = false
}

variable "schedule_expression" {
  type    = string
  default = "rate(1 minute)"
}
