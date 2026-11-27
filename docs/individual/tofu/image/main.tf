terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "timecapsule"
      Environment = "dev"
      Lab         = "individual"
      Owner       = "lesik"
    }
  }
}

data "aws_instance" "app" {
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-app"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

resource "aws_ami_from_instance" "app" {
  name                    = var.ami_name
  description             = "TimeCapsule application with Secrets Manager credentials"
  source_instance_id      = data.aws_instance.app.id
  snapshot_without_reboot = false

  tags = {
    Name        = var.ami_name
    Project     = "timecapsule"
    Environment = "dev"
    Lab         = "individual"
    Owner       = "lesik"
  }
}

output "ami_id" {
  value = aws_ami_from_instance.app.id
}

output "ami_name" {
  value = aws_ami_from_instance.app.name
}
