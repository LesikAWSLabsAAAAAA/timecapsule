variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "run_fleet" {
  description = "Create the chargeable ALB and ASG; set false after collecting evidence."
  type        = bool
  default     = false
}

variable "ami_name" {
  type        = string
  description = "AMI built by ../image and containing the Secrets Manager code."
  default     = "timecapsule-dev-app-individual"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type    = string
  default = "nitrokey"
}

variable "app_role_name" {
  type        = string
  description = "Existing instance role/profile with the Secrets Manager policy."
  default     = "timecapsule-dev-app-role"
}

variable "vpc_name" {
  type    = string
  default = "timecapsule-dev-vpc"
}

variable "bastion_sg_name" {
  type    = string
  default = "bastion-sg"
}

variable "rds_sg_name" {
  type    = string
  default = "timecapsule-dev-rds-sg"
}

variable "health_check_path" {
  type    = string
  default = "/health"
}
