# Lab 5, part 1: temporary sandbox.
#   app-server (existing) -> lab5-db / lab5-db-replica / lab5-db-restore
# Everything here is destroyed at the end of part 1.

locals {
  subnet_group_name = "lab5-db-subnets"
  web_sg_name       = "lab5-web-sg"
  rds_sg_name       = "lab5-rds-sg"
}

# ---------------------------------------------------------------------------
# Security groups (task 1)
# ---------------------------------------------------------------------------

resource "aws_security_group" "web" {
  name        = local.web_sg_name
  description = "Lab 5 sandbox: source security group for the database clients"
  vpc_id      = data.aws_vpc.main.id

  egress {
    description = "Allow the web-server to reach RDS and package mirrors"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = local.web_sg_name
  })
}

# An additional group on the existing app-server ENI. The original web-sg stays
# attached; OpenTofu removes only this association on destroy.
resource "aws_network_interface_sg_attachment" "web" {
  security_group_id    = aws_security_group.web.id
  network_interface_id = data.aws_instance.client.network_interface_id
}

resource "aws_security_group" "rds" {
  name        = local.rds_sg_name
  description = "Lab 5 sandbox: PostgreSQL only from lab5-web-sg"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from the lab 5 web-server"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "Default egress; RDS does not initiate connections"
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
# Subnet group and primary sandbox database (task 2)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "lab5" {
  name        = local.subnet_group_name
  description = "Lab 5 sandbox private subnets"
  subnet_ids  = [data.aws_subnet.private_a.id, data.aws_subnet.private_b.id]

  tags = merge(var.tags, {
    Name = local.subnet_group_name
  })
}

resource "aws_db_instance" "sandbox" {
  identifier = "lab5-db"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name             = "lab5"
  username            = "dbadmin"
  password_wo         = var.db_admin_password
  password_wo_version = 1
  port                = 5432

  db_subnet_group_name   = aws_db_subnet_group.lab5.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zone      = "eu-central-1a"
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = var.backup_retention_days
  backup_window           = "01:00-01:30"
  maintenance_window      = "sun:03:00-sun:03:30"

  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = var.enable_deletion_protection
  skip_final_snapshot        = true
  copy_tags_to_snapshot      = true

  tags = merge(var.tags, {
    Name = "lab5-db"
  })

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ---------------------------------------------------------------------------
# Read replica (task 4)
# ---------------------------------------------------------------------------

resource "aws_db_instance" "replica" {
  count = var.create_replica ? 1 : 0

  identifier          = "lab5-db-replica"
  replicate_source_db = aws_db_instance.sandbox.arn

  engine         = "postgres"
  instance_class = "db.t4g.micro"

  db_subnet_group_name   = aws_db_subnet_group.lab5.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zone      = "eu-central-1b"
  publicly_accessible    = false
  storage_encrypted      = true

  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = merge(var.tags, {
    Name = "lab5-db-replica"
  })

  timeouts {
    create = "60m"
    delete = "60m"
  }
}

# ---------------------------------------------------------------------------
# Point-in-time restore (task 5)
# ---------------------------------------------------------------------------

resource "aws_db_instance" "restore" {
  count = var.create_restore ? 1 : 0

  identifier     = "lab5-db-restore"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.lab5.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period    = 0
  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = false
  skip_final_snapshot        = true

  restore_to_point_in_time {
    source_db_instance_identifier = aws_db_instance.sandbox.identifier
    restore_time                  = var.restore_time
  }

  lifecycle {
    precondition {
      condition     = !var.create_replica && can(formatdate("YYYY", var.restore_time)) && endswith(var.restore_time, "Z")
      error_message = "Disable the replica and supply a UTC RFC3339 restore_time before enabling PITR."
    }
  }

  tags = merge(var.tags, {
    Name = "lab5-db-restore"
  })

  timeouts {
    create = "60m"
    delete = "60m"
  }
}
