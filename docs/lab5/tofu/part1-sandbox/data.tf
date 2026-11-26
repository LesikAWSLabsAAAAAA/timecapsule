# All of these resources were created in lab 3. Part 1 only reads them.

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

# The existing app-server is the sandbox's psql client for this deployment.
# Only its temporary lab5-web-sg association is managed by this stack.
data "aws_instance" "client" {
  filter {
    name   = "tag:Name"
    values = ["timecapsule-dev-app"]
  }
}
