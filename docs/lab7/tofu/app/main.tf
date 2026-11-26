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
    tags = { Lab = "lab7", Project = "timecapsule", Environment = "dev" }
  }
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_vpc" "app" {
  tags = { Name = "timecapsule-dev-vpc" }
}

data "aws_subnet" "private" {
  for_each = toset(["a", "b"])
  vpc_id   = data.aws_vpc.app.id
  tags     = { Name = "timecapsule-dev-private-${each.key}" }
}

data "aws_security_group" "rds" {
  vpc_id = data.aws_vpc.app.id
  name   = "timecapsule-dev-rds-sg"
}

data "aws_db_instance" "app" {
  db_instance_identifier = "timecapsule-dev-rds"
}

data "aws_iam_role" "app" {
  name = "timecapsule-dev-app-role"
}

resource "aws_sns_topic" "events" {
  name = "timecapsule-dev-events"
}

resource "aws_sqs_queue" "dlq" {
  name                      = "timecapsule-dev-mail-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "mail" {
  name                       = "timecapsule-dev-mail"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "mail" {
  queue_url = aws_sqs_queue.mail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventsTopic"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.mail.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "mail" {
  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.mail.arn
  raw_message_delivery = true
  filter_policy_scope  = "MessageBody"
  filter_policy        = jsonencode({ eventType = ["capsule.sealed"] })
  depends_on           = [aws_sqs_queue_policy.mail]
}

resource "aws_sns_topic_subscription" "opened_email" {
  topic_arn           = aws_sns_topic.events.arn
  protocol            = "email"
  endpoint            = var.email
  filter_policy_scope = "MessageBody"
  filter_policy       = jsonencode({ responsePayload = { eventType = ["capsules.opened"] } })
}

resource "aws_security_group" "lambda" {
  name        = "timecapsule-dev-lambda-sg"
  description = "Database access for lab7 Lambda functions"
  vpc_id      = data.aws_vpc.app.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_db" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = data.aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# Standalone rule: do not take ownership of the RDS security group.
resource "aws_vpc_security_group_ingress_rule" "rds_lambda" {
  security_group_id            = data.aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from lab7 Lambda"
}

locals {
  lambda_assume = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  functions = {
    mailer = { zip = var.mailer_zip, timeout = 30 }
    opener = { zip = var.opener_zip, timeout = 60 }
  }
}

resource "aws_iam_role" "lambda" {
  for_each           = local.functions
  name               = "timecapsule-dev-${each.key}-role"
  assume_role_policy = local.lambda_assume
}

# AWS managed policy includes CloudWatch logging and Lambda VPC ENI permissions.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  for_each   = local.functions
  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "mailer_sqs" {
  name = "consume-mail-queue"
  role = aws_iam_role.lambda["mailer"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.mail.arn
    }]
  })
}

resource "aws_iam_role_policy" "opener_sns" {
  name = "publish-success"
  role = aws_iam_role.lambda["opener"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.events.arn
    }]
  })
}

# Add only this policy to the pre-existing instance role.
resource "aws_iam_role_policy" "app_sns" {
  name = "timecapsule-dev-app-events"
  role = data.aws_iam_role.app.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.events.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.functions
  name              = "/aws/lambda/timecapsule-dev-${each.key}"
  retention_in_days = 14
}

resource "aws_lambda_function" "app" {
  for_each         = local.functions
  function_name    = "timecapsule-dev-${each.key}"
  role             = aws_iam_role.lambda[each.key].arn
  filename         = each.value.zip
  source_code_hash = filebase64sha256(each.value.zip)
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  handler          = "handler.handler"
  timeout          = each.value.timeout
  memory_size      = 256
  vpc_config {
    subnet_ids         = [for subnet in data.aws_subnet.private : subnet.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
  environment {
    variables = {
      DB_HOST        = data.aws_db_instance.app.address
      DB_PORT        = "5432"
      DB_NAME        = var.db_name
      DB_USER        = var.db_user
      DB_PASSWORD    = each.key == "mailer" && var.simulate_mail_failure ? "lab7-intentionally-incorrect-password" : var.db_password
      DB_SSLMODE     = "verify-full"
      DB_SSLROOTCERT = var.db_sslrootcert
    }
  }
  depends_on = [aws_iam_role_policy_attachment.lambda_vpc, aws_cloudwatch_log_group.lambda, aws_vpc_security_group_ingress_rule.rds_lambda]
}

resource "aws_lambda_event_source_mapping" "mail" {
  event_source_arn        = aws_sqs_queue.mail.arn
  function_name           = aws_lambda_function.app["mailer"].arn
  batch_size              = 1
  enabled                 = var.enable_mail_trigger
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config {
    maximum_concurrency = 2
  }
  depends_on = [aws_iam_role_policy.mailer_sqs]
}

resource "aws_lambda_function_event_invoke_config" "opener" {
  function_name = aws_lambda_function.app["opener"].function_name
  destination_config {
    on_success {
      destination = aws_sns_topic.events.arn
    }
  }
  depends_on = [aws_iam_role_policy.opener_sns]
}

resource "aws_iam_role" "scheduler" {
  name = "timecapsule-dev-lab7-opener-scheduler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule-group/default" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-opener"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.app["opener"].arn
    }]
  })
}

resource "aws_scheduler_schedule" "opener" {
  name                         = "timecapsule-dev-open-capsules"
  group_name                   = "default"
  state                        = var.enable_scheduler ? "ENABLED" : "DISABLED"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_lambda_function.app["opener"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
  depends_on = [aws_iam_role_policy.scheduler, aws_lambda_function_event_invoke_config.opener]
}
