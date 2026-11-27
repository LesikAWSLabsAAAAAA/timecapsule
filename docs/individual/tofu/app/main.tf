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

data "aws_vpc" "app" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnet" "public" {
  for_each = toset(["a", "b"])
  vpc_id   = data.aws_vpc.app.id
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-public-${each.key}"]
  }
}

data "aws_security_group" "bastion" {
  vpc_id = data.aws_vpc.app.id
  name   = var.bastion_sg_name
}

data "aws_security_group" "rds" {
  vpc_id = data.aws_vpc.app.id
  name   = var.rds_sg_name
}

data "aws_ami" "app" {
  owners      = ["self"]
  most_recent = true
  filter {
    name   = "name"
    values = [var.ami_name]
  }
}

resource "aws_security_group" "alb" {
  name        = "timecapsule-dev-individual-alb-sg"
  description = "Public HTTP access to the individual-work ALB"
  vpc_id      = data.aws_vpc.app.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name        = "timecapsule-dev-individual-app-sg"
  description = "Application servers for the individual work"
  vpc_id      = data.aws_vpc.app.id

  ingress {
    description     = "HTTP from the ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH from the bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [data.aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Standalone rule: do not take ownership of the shared RDS security group.
resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id            = data.aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from individual app fleet"
}

resource "aws_lb_target_group" "app" {
  name     = "timecapsule-dev-individual-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.app.id

  health_check {
    path                = var.health_check_path
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_launch_template" "app" {
  name          = "timecapsule-dev-individual-lt"
  image_id      = data.aws_ami.app.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.app_role_name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "timecapsule-dev-individual-app"
      Project     = "timecapsule"
      Environment = "dev"
      Lab         = "individual"
      Owner       = "lesik"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "timecapsule-dev-individual-app"
      Project     = "timecapsule"
      Environment = "dev"
      Lab         = "individual"
      Owner       = "lesik"
    }
  }
}

resource "aws_lb" "app" {
  count              = var.run_fleet ? 1 : 0
  name               = "timecapsule-dev-individual-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in data.aws_subnet.public : subnet.id]
}

resource "aws_lb_listener" "app" {
  count             = var.run_fleet ? 1 : 0
  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_group" "app" {
  count                     = var.run_fleet ? 1 : 0
  name                      = "timecapsule-dev-individual-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 4
  vpc_zone_identifier       = [for subnet in data.aws_subnet.public : subnet.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  tag {
    key                 = "Name"
    value               = "timecapsule-dev-individual-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Lab"
    value               = "individual"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "timecapsule"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "dev"
    propagate_at_launch = true
  }

  tag {
    key                 = "Owner"
    value               = "lesik"
    propagate_at_launch = true
  }

  depends_on = [
    aws_lb_listener.app,
    aws_vpc_security_group_ingress_rule.rds_from_app,
  ]
}

resource "aws_autoscaling_policy" "requests" {
  count                  = var.run_fleet ? 1 : 0
  name                   = "timecapsule-dev-individual-requests"
  autoscaling_group_name = aws_autoscaling_group.app[0].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app[0].arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 50
  }
}

output "alb_dns" {
  value = try(aws_lb.app[0].dns_name, null)
}

output "asg_name" {
  value = try(aws_autoscaling_group.app[0].name, null)
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "launch_template_id" {
  value = aws_launch_template.app.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}
