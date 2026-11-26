# Final architecture of lab 5, part 2:
#   app-server (existing) -> timecapsule-dev-rds (private subnets, PostgreSQL 16)
#   db.timecapsule.internal is a CNAME to the RDS endpoint
#   EventBridge Scheduler stops the instance every night at 23:00 Europe/Chisinau

locals {
  db_identifier     = "timecapsule-dev-rds"
  subnet_group_name = "timecapsule-dev-db-subnets"
  rds_sg_name       = "timecapsule-dev-rds-sg"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "app" {
  name        = local.subnet_group_name
  description = "Private subnets for the TimeCapsule application database"
  subnet_ids  = [data.aws_subnet.private_a.id, data.aws_subnet.private_b.id]

  tags = merge(var.tags, {
    Name = local.subnet_group_name
  })
}

resource "aws_security_group" "rds" {
  name        = local.rds_sg_name
  description = "PostgreSQL only from the application security group"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app-server"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.app.id]
  }

  egress {
    description = "RDS does not initiate connections; keep the default egress for AWS health checks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = local.rds_sg_name
  })
}

# ---------------------------------------------------------------------------
# RDS instance
# ---------------------------------------------------------------------------

resource "aws_db_instance" "app" {
  identifier = local.db_identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 0 # storage autoscaling is explicitly disabled
  storage_type          = "gp3"
  storage_encrypted     = true

  # No initial database: the `timecapsule` database is created in task 8.
  username            = "dbadmin"
  password_wo         = var.db_admin_password
  password_wo_version = 1
  port                = 5432

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zone      = "eu-central-1a"
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = var.backup_retention_days
  backup_window           = "01:00-01:30" # UTC
  maintenance_window      = "sun:03:00-sun:03:30"

  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = true
  skip_final_snapshot        = true
  copy_tags_to_snapshot      = true

  tags = merge(var.tags, {
    Name = local.db_identifier
  })

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ---------------------------------------------------------------------------
# Route 53: db.timecapsule.internal now points to RDS
# ---------------------------------------------------------------------------
# The old A record is imported once. Only the cutover plan changes its type.

resource "aws_route53_record" "db" {
  zone_id = data.aws_route53_zone.internal.zone_id
  name    = "db.timecapsule.internal"
  type    = var.switch_database_dns ? "CNAME" : "A"
  ttl     = 300
  records = var.switch_database_dns ? [aws_db_instance.app.address] : [var.legacy_db_ip]
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler: nightly stop
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule-group/default"]
    }
  }
}

resource "aws_iam_policy" "rds_stop" {
  name        = "timecapsule-dev-rds-stop"
  description = "Allow EventBridge Scheduler to stop only timecapsule-dev-rds"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StopOnlyThisDatabase"
        Effect   = "Allow"
        Action   = "rds:StopDBInstance"
        Resource = aws_db_instance.app.arn
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "timecapsule-dev-rds-stop"
  })
}

resource "aws_iam_role" "scheduler" {
  name                 = "timecapsule-dev-scheduler-role"
  description          = "Role assumed by EventBridge Scheduler for the nightly RDS stop"
  assume_role_policy   = data.aws_iam_policy_document.scheduler_assume_role.json
  max_session_duration = 3600

  tags = merge(var.tags, {
    Name = "timecapsule-dev-scheduler-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_stop" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.rds_stop.arn
}

resource "aws_scheduler_schedule" "nightly_stop" {
  name        = "timecapsule-dev-rds-nightly-stop"
  group_name  = "default"
  description = "Stops timecapsule-dev-rds every evening to limit RDS cost"

  schedule_expression          = var.stop_schedule_expression
  schedule_expression_timezone = "Europe/Chisinau"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      DbInstanceIdentifier = aws_db_instance.app.identifier
    })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }

  depends_on = [aws_iam_role_policy_attachment.rds_stop]
}
