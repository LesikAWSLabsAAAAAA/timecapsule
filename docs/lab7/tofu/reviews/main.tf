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
    tags = { Lab = "lab7" }
  }
}

variable "email" {
  type      = string
  sensitive = true
}

variable "enable_trigger" {
  type    = bool
  default = false
}

resource "aws_sns_topic" "reviews" {
  name = "lab7-reviews"
}

resource "aws_sqs_queue" "dlq" {
  name                      = "lab7-reviews-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "reviews" {
  name                       = "lab7-reviews-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "reviews" {
  queue_url = aws_sqs_queue.reviews.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OnlyReviewsTopic"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.reviews.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.reviews.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "queue" {
  topic_arn            = aws_sns_topic.reviews.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.reviews.arn
  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.reviews]
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn     = aws_sns_topic.reviews.arn
  protocol      = "email"
  endpoint      = var.email
  filter_policy = jsonencode({ rating = [{ numeric = ["<", 3] }] })
}

resource "aws_iam_role" "worker" {
  name = "lab7-review-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/lab7-review-worker"
  retention_in_days = 7
}

resource "aws_lambda_function" "worker" {
  function_name    = "lab7-review-worker"
  role             = aws_iam_role.worker.arn
  runtime          = "python3.13"
  handler          = "worker.handler"
  filename         = "${path.module}/worker.zip"
  source_code_hash = filebase64sha256("${path.module}/worker.zip")
  timeout          = 10
  depends_on       = [aws_iam_role_policy_attachment.worker, aws_cloudwatch_log_group.worker]
}

resource "aws_lambda_event_source_mapping" "reviews" {
  event_source_arn = aws_sqs_queue.reviews.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 1
  enabled          = var.enable_trigger
}

output "topic_arn" {
  value = aws_sns_topic.reviews.arn
}

output "queue_url" {
  value = aws_sqs_queue.reviews.id
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}
