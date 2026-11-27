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

data "aws_db_instance" "app" {
  db_instance_identifier = var.db_instance_identifier
}

data "aws_iam_role" "app" {
  name = var.app_role_name
}

resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  description             = "TimeCapsule application database credentials"
  recovery_window_in_days = 0 # lab cleanup: allow an immediate destroy

  tags = {
    Name = var.secret_name
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_user
    password = var.db_password
    host     = data.aws_db_instance.app.address
    port     = data.aws_db_instance.app.port
    dbname   = var.db_name
    engine   = "postgres"
  })
}

locals {
  allow_statement = {
    Sid      = "ReadTimecapsuleDatabaseSecret"
    Effect   = "Allow"
    Action   = "secretsmanager:GetSecretValue"
    Resource = aws_secretsmanager_secret.db.arn
    Condition = {
      StringEquals = {
        "aws:RequestedRegion" = var.region
      }
      Bool = {
        "aws:SecureTransport" = "true"
      }
    }
  }

  # Used only for the B4 failure exercise. An explicit Deny wins over any
  # other identity policy on the instance role.
  deny_statement = {
    Sid      = "DenyTimecapsuleDatabaseSecret"
    Effect   = "Deny"
    Action   = "secretsmanager:GetSecretValue"
    Resource = "*"
  }
}

resource "aws_iam_policy" "app_secret" {
  name        = "timecapsule-dev-app-secretsmanager"
  description = "Read only the TimeCapsule database password from Secrets Manager"

  policy = var.enable_secret_access ? jsonencode({
    Version   = "2012-10-17"
    Statement = [local.allow_statement]
    }) : jsonencode({
    Version   = "2012-10-17"
    Statement = [local.deny_statement]
  })

  tags = {
    Name = "timecapsule-dev-app-secretsmanager"
  }
}

resource "aws_iam_role_policy_attachment" "app_secret" {
  role       = data.aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_secret.arn
}
