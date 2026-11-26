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

data "aws_vpc" "lab" {
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-vpc"]
  }
}

data "aws_subnet" "public" {
  for_each = toset(["a", "b"])
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-public-${each.key}"]
  }
  vpc_id = data.aws_vpc.lab.id
}

data "aws_security_group" "bastion" {
  vpc_id = data.aws_vpc.lab.id
  name   = "bastion-sg"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "alb" {
  name   = "lab6-alb-sg"
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

resource "aws_security_group" "web" {
  name   = "lab6-web-sg"
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

resource "aws_lb_target_group" "web" {
  name     = "lab6-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.lab.id
  health_check {
    path     = "/health"
    interval = 10
  }
}

resource "aws_lb" "web" {
  name               = "lab6-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in data.aws_subnet.public : s.id]
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_launch_template" "web" {
  name          = "lab6-lt"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.micro"
  key_name      = "nitrokey"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }
  metadata_options {
    http_tokens = "required"
  }
  user_data = base64encode(file("${path.module}/user-data.sh"))
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "lab6-web", Lab = "lab6" }
  }
  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "lab6-web", Lab = "lab6" }
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "lab6-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 4
  vpc_zone_identifier       = [for s in data.aws_subnet.public : s.id]
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }
  tag {
    key                 = "Lab"
    value               = "lab6"
    propagate_at_launch = true
  }
  depends_on = [aws_lb_listener.web]
}

resource "aws_autoscaling_policy" "requests" {
  name                   = "lab6-requests"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.web.arn_suffix}/${aws_lb_target_group.web.arn_suffix}"
    }
    target_value = 50
  }
}

output "alb_dns" {
  value = aws_lb.web.dns_name
}
