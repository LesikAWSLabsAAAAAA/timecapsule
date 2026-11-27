variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "ami_name" {
  type        = string
  description = "Unique AMI name; change it before rebuilding the image."
  default     = "timecapsule-dev-app-individual"
}
