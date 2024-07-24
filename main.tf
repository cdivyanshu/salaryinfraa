# SALARY


#Salary-Security Group

resource "aws_security_group" "salary_security_group" {
  vpc_id = aws_vpc.ot_microservices_dev.id
  name = "salary-security-group"

  tags = {
    Name = "salary-security-group"
  }
  
  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    security_groups = [aws_security_group.alb_security_group.id]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    security_groups = [aws_security_group.bastion_security_group.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = ["::/0"]
  }
}

# instance

resource "aws_instance" "salary_instance" {
  # ami to be replaced with actual bastion ami
  ami           = "ami-0ea8cf939c4f34d5d"
  subnet_id = aws_subnet.application_subnet.id
  vpc_security_group_ids = [aws_security_group.salary_security_group.id]
  instance_type = "t2.micro"
  key_name = "backend"

  tags = {
    Name = "Salary"
  }
}

# target group and attachment

resource "aws_lb_target_group" "salary_target_group" {
  name     = "salary-tg"
  port     = 80
  protocol = "HTTP"
  target_type = "instance"
  vpc_id   = aws_vpc.ot_microservices_dev.id
}

resource "aws_lb_target_group_attachment" "salary_target_group_attachment" {
  target_group_arn = aws_lb_target_group.salary_target_group.arn
  target_id        = aws_instance.salary_instance.id
  port             = 8080
}

# listener rule

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


# launch template for Salary

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
    subnet_id                   = aws_subnet.application_subnet.id
    associate_public_ip_address = false
    security_groups             = [aws_security_group.salary_security_group.id]
  }

  key_name      = "backend"
  # ami to be replaced with actual ami currently not right
  image_id      = "ami-0ea8cf939c4f34d5d"
  instance_type = "t2.micro"

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "SalaryASG"
    }
  }
}


# auto scaling for Salary

resource "aws_autoscaling_group" "salary_autoscaling" {
  name                      = "salary-autoscale"
  max_size                  = 2
  min_size                  = 0
  desired_capacity = 0
  health_check_grace_period = 300
  launch_template {
    id      = aws_launch_template.salary_launch_template.id
    version = "$Default"
  }
  vpc_zone_identifier = [aws_subnet.application_subnet.id]
  target_group_arns = [aws_lb_target_group.salary_target_group.arn]
}

resource "aws_autoscaling_policy" "salary" {
  name                   = "salary-autoscaling-policy"
  policy_type            = "TargetTrackingScaling"
  adjustment_type        = "ChangeInCapacity"
  estimated_instance_warmup = 300
  autoscaling_group_name = aws_autoscaling_group.salary_autoscaling.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}
