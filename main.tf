provider "aws" {
  region = "us-west-2"
}

# Define the VPC
resource "aws_vpc" "ot_microservices_dev" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ot_microservices_dev"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.ot_microservices_dev.id

  tags = {
    Name = "internet-gateway"
  }
}

# Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.ot_microservices_dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "route-table"
  }
}

# Associate Route Table with Subnets
resource "aws_route_table_association" "application_subnet_association_a" {
  subnet_id      = aws_subnet.application_subnet_a.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "application_subnet_association_b" {
  subnet_id      = aws_subnet.application_subnet_b.id
  route_table_id = aws_route_table.route_table.id
}

# Subnets
resource "aws_subnet" "application_subnet_a" {
  vpc_id            = aws_vpc.ot_microservices_dev.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "application-subnet-a"
  }
}

resource "aws_subnet" "application_subnet_b" {
  vpc_id            = aws_vpc.ot_microservices_dev.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "application-subnet-b"
  }
}

# ALB Security Group
resource "aws_security_group" "alb_security_group" {
  vpc_id = aws_vpc.ot_microservices_dev.id
  name   = "alb-security-group"

  tags = {
    Name = "alb-security-group"
  }

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

# ALB Load Balancer
resource "aws_lb" "front_end" {
  name               = "frontend-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_security_group.id]
  subnets            = [
    aws_subnet.application_subnet_a.id,
    aws_subnet.application_subnet_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "frontend-lb"
  }
}

# ALB Listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.front_end.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Default action"
      status_code  = "200"
    }
  }
}

# Salary Security Group
resource "aws_security_group" "salary_security_group" {
  vpc_id = aws_vpc.ot_microservices_dev.id
  name   = "salary-security-group"

  tags = {
    Name = "salary-security-group"
  }
  
  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_security_group.id]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_security_group.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

# Salary Instance
resource "aws_instance" "salary_instance" {
  ami           = "ami-0ea8cf939c4f34d5d"  # Replace with the correct AMI
  subnet_id     = aws_subnet.application_subnet_a.id
  vpc_security_group_ids = [aws_security_group.salary_security_group.id]
  instance_type = "t2.micro"
  key_name      = "backend"  # Replace with the correct key name

  tags = {
    Name = "Salary"
  }
}

# Salary Target Group
resource "aws_lb_target_group" "salary_target_group" {
  name        = "salary-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.ot_microservices_dev.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold    = 2
    unhealthy_threshold  = 2
  }
}

# Salary Target Group Attachment
resource "aws_lb_target_group_attachment" "salary_target_group_attachment" {
  target_group_arn = aws_lb_target_group.salary_target_group.arn
  target_id        = aws_instance.salary_instance.id
  port             = 8080
}

# Salary Listener Rule
resource "aws_lb_listener_rule" "salary_rule" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.salary_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/salary/*"]
    }
  }
}

# Salary Launch Template
resource "aws_launch_template" "salary_launch_template" {
  name = "salary-template"

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 10
      volume_type = "gp3"
    }
  }

  network_interfaces {
    subnet_id                   = aws_subnet.application_subnet_a.id
    associate_public_ip_address = false
    security_groups             = [aws_security_group.salary_security_group.id]
  }

  key_name      = "backend"  # Replace with the correct key name
  image_id      = "ami-0ea8cf939c4f34d5d"  # Re
