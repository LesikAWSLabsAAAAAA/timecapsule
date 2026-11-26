# The VPC, subnets, EC2 instances and the hosted zone were created in labs 3-4.
# OpenTofu only reads them; it does not manage or recreate them.

data "aws_vpc" "main" {
  tags = {
    Name = "timecapsule-dev-vpc"
  }
}

data "aws_subnet" "private_a" {
  vpc_id = data.aws_vpc.main.id
  tags = {
    Name = "timecapsule-dev-private-a"
  }
}

data "aws_subnet" "private_b" {
  vpc_id = data.aws_vpc.main.id
  tags = {
    Name = "timecapsule-dev-private-b"
  }
}

# Application server from lab 3. Its security group is the only allowed source
# for PostgreSQL on the RDS instance.
data "aws_instance" "app" {
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-app"]
  }
}

data "aws_security_group" "app" {
  vpc_id = data.aws_vpc.main.id

  filter {
    name   = "group-name"
    values = ["web-sg"]
  }
}

data "aws_route53_zone" "internal" {
  name         = "timecapsule.internal"
  private_zone = true
}
