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

resource "aws_dynamodb_table" "sessions" {
  name         = "timecapsule-dev-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
  ttl {
    attribute_name = "expires"
    enabled        = true
  }
}

data "aws_iam_policy_document" "sessions" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.sessions.arn]
  }
}

resource "aws_iam_policy" "sessions" {
  name   = "timecapsule-dev-app-sessions"
  policy = data.aws_iam_policy_document.sessions.json
}

resource "aws_iam_role_policy_attachment" "sessions" {
  role       = "timecapsule-dev-app-role"
  policy_arn = aws_iam_policy.sessions.arn
}
