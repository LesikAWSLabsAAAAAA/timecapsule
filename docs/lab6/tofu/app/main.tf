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

variable "run_fleet" {
  description = "Create the chargeable load balancer and ASG; set false after the lab."
  type        = bool
  default     = false
}

data "aws_vpc" "lab" {
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-vpc"]
  }
}
data "aws_subnet" "public" {
  for_each = toset(["a", "b"])
  vpc_id   = data.aws_vpc.lab.id
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-public-${each.key}"]
  }
}
data "aws_security_group" "bastion" {
  vpc_id = data.aws_vpc.lab.id
  name   = "bastion-sg"
}
data "aws_security_group" "rds" {
  vpc_id = data.aws_vpc.lab.id
  name   = "timecapsule-dev-rds-sg"
}
data "aws_ami" "app" {
  owners      = ["self"]
  most_recent = true
  filter {
    name   = "name"
    values = ["timecapsule-dev-app-lab6"]
  }
}

resource "aws_security_group" "alb" {
  name   = "timecapsule-dev-lab6-alb-sg"
  vpc_id = data.aws_vpc.lab.id
  ingress {
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
  name   = "timecapsule-dev-lab6-app-sg"
  vpc_id = data.aws_vpc.lab.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
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
resource "aws_vpc_security_group_ingress_rule" "rds_from_fleet" {
  security_group_id            = data.aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from lab6 app fleet"
}
resource "aws_lb_target_group" "app" {
  name     = "timecapsule-dev-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.lab.id
  health_check {
    path     = "/health"
    interval = 10
  }
}
resource "aws_launch_template" "app" {
  name          = "timecapsule-dev-app-lt"
  image_id      = data.aws_ami.app.id
  instance_type = "t3.micro"
  key_name      = "nitrokey"
  iam_instance_profile {
    name = "timecapsule-dev-app-role"
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
    tags          = { Name = "timecapsule-dev-app-asg", Lab = "lab6" }
  }
  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "timecapsule-dev-app-asg", Lab = "lab6" }
  }
}
resource "aws_lb" "app" {
  count              = var.run_fleet ? 1 : 0
  name               = "timecapsule-dev-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in data.aws_subnet.public : s.id]
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
  name                      = "timecapsule-dev-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 4
  vpc_zone_identifier       = [for s in data.aws_subnet.public : s.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }
  tag {
    key                 = "Lab"
    value               = "lab6"
    propagate_at_launch = true
  }
  depends_on = [aws_lb_listener.app, aws_vpc_security_group_ingress_rule.rds_from_fleet]
}
resource "aws_autoscaling_policy" "requests" {
  count                  = var.run_fleet ? 1 : 0
  name                   = "timecapsule-dev-requests"
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
