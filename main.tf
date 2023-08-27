resource "aws_vpc" "myvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "MYVPC"
  }
}

resource "aws_subnet" "pubsub" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
    availability_zone = "ap-south-1a"
  tags = {
    Name = "MYVPC-PUBSUB"
  }
}

resource "aws_subnet" "prisub" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.2.0/24"
    availability_zone = "ap-south-1b"
  tags = {
    Name = "MYVPC-PRISUB"
  }
}

resource "aws_internet_gateway" "tigw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "MYVPC-TIGW"
  }
}

resource "aws_route_table" "myvpcrt" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tigw.id
  }

  tags = {
    Name = "MYVPC-RT"
  }
}

resource "aws_route_table_association" "rtasso" {
  subnet_id      = aws_subnet.pubsub.id
  route_table_id = aws_route_table.myvpcrt.id
}

resource "aws_eip" "nateip" {
  vpc   = "true"
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.nateip.id
  subnet_id     = aws_subnet.prisub.id

  tags = {
    Name = "MYVPC-NATGW"
  }
}

resource "aws_route_table" "myvpcprirt" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.natgw.id
  }

  tags = {
    Name = "MYVPC-PRIRT"
  }
}

resource "aws_route_table_association" "prirtasso" {
  subnet_id      = aws_subnet.prisub.id
  route_table_id = aws_route_table.myvpcprirt.id
}

resource "aws_security_group" "myvpcallow_all" {
  name        = "myvpcallow_all"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ALLOW_ALL"
  }
}

resource "aws_instance" "instance1"{
    ami = "ami-0f5ee92e2d63afc18"
    instance_type = "t2.micro"
    key_name = "080823"
    subnet_id = aws_subnet.pubsub.id
    vpc_security_group_ids = [aws_security_group.myvpcallow_all.id]
    associate_public_ip_address = "true"
    user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install docker.io -y
              sudo service docker start
              sudo usermod -a -G docker ubuntu
              docker pull pakas142/devopsathon:latest
              docker run -d -p 5000:5000 pakas142/devopsathon:latest
              EOF
}

resource "aws_instance" "instance2"{
    ami = "ami-0f5ee92e2d63afc18"
    instance_type = "t2.micro"
    key_name = "080823"
    subnet_id = aws_subnet.prisub.id
    vpc_security_group_ids = [aws_security_group.myvpcallow_all.id]
}

resource "aws_elb" "elb" {
  name               = "dev-terraform-elb"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = ["${aws_instance.instance1.id}", "${aws_instance.instance2.id}"]
  cross_zone_load_balancing   = true
  idle_timeout                = 40

  tags = {
    Name = "devops-terraform-elb"
  }
}
resource "aws_launch_configuration" "asg_conf" {
  name_prefix = "asg-config"
  image_id      = "ami-0f5ee92e2d63afc18"
  instance_type = "t2.micro"
  key_name = "080823"
}

resource "aws_autoscaling_group" "asg" {
  name                      = "asg-terraform-devopsathon"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.asg_conf.name
  vpc_zone_identifier       = [aws_subnet.pubsub.id, aws_subnet.prisub.id]

tag {
    key                 = "asg"
    value               = "ec2 instance"
    propagate_at_launch = true
    }
}
resource "aws_autoscaling_policy" "asg_policy" {
  name                   = "devopsathon-terraform-asg"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
  policy_type            = "SimpleScaling"
}

resource "aws_cloudwatch_metric_alarm" "cw_alarm" {
  alarm_name                = "terraform-cw-alarm"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 120
  statistic                 = "Average"
  threshold                 = 60
  dimensions = {
    "AutoScalingGroupName" = "$(aws_autoscaling_group.asg.name)"
  }
}
resource "aws_sns_topic" "cpu_sns" {
  name = "sns-updates-topic"
  display_name = "autoscaling sns topic"
}

resource "aws_autoscaling_notification" "asg_notifications" {
  group_names = [aws_autoscaling_group.asg.name]
  topic_arn = aws_sns_topic.cpu_sns.arn

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
}
