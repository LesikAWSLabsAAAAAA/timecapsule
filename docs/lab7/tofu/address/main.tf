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
    tags = {
      Project     = "timecapsule"
      Environment = "dev"
      Lab         = "lab7"
    }
  }
}

resource "aws_eip" "app" {
  domain   = "vpc"
  instance = "i-0ab69e8474108b35c"
  tags     = { Name = "timecapsule-dev-app-eip" }
}

output "app_public_ip" {
  value = aws_eip.app.public_ip
}
