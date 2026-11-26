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
  region = "eu-central-1"
  default_tags {
    tags = { Lab = "lab6" }
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
  name                    = "timecapsule-dev-app-lab6"
  source_instance_id      = data.aws_instance.app.id
  snapshot_without_reboot = false
  tags                    = { Name = "timecapsule-dev-app-lab6" }
}

output "ami_id" {
  value = aws_ami_from_instance.app.id
}
