## 0. General

provider "aws" {
  region     = var.aws_region
  access_key = var.access_key
  secret_key = var.secret_key
}

#ami will automatically be choosen
data "aws_ami" "amazon-linux-2" {
 most_recent = true
 owners = ["amazon"]

 
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }


 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
}
#gives az in choosen region
data "aws_availability_zones" "all" {}

# # 1. Create vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
   tags = {
    Name = "production"
   }
 }


# # 2. Create Internet Gateway

 resource "aws_internet_gateway" "gw" {
   vpc_id = aws_vpc.prod-vpc.id
 }

# # 3. Create Custom Route Table

 resource "aws_route_table" "prod-route-table" {
   vpc_id = aws_vpc.prod-vpc.id

   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.gw.id
   }

   route {
     ipv6_cidr_block = "::/0"
     gateway_id      = aws_internet_gateway.gw.id
   }

   tags = {
     Name = "Prod"
   }
 }

# # 4. Create a Subnet 

resource "aws_subnet" "subnet-public" {
   vpc_id            = aws_vpc.prod-vpc.id
   cidr_block        = "10.0.1.0/24"

   tags = {
     Name = "prod-subnet"
   }
 }

# # 5. Associate subnet with Route Table
 resource "aws_route_table_association" "a" {
   subnet_id      = aws_subnet.subnet-public.id
   route_table_id = aws_route_table.prod-route-table.id
 }

# # 6. Create Security Group to allow port 22 only own IP , 80,443 elb SG
 resource "aws_security_group" "allow_web" {
   name        = "allow_web_traffic"
   description = "Allow Web inbound traffic"
   vpc_id      = aws_vpc.prod-vpc.id
  
   ingress {
     description = "HTTPS"
     from_port   = 443
     to_port     = 443
     protocol    = "tcp"
     security_groups = [aws_security_group.elb.id]

   }
   ingress {
     description = "HTTP"
     from_port   = 80
     to_port     = 80
     protocol    = "tcp"
     security_groups = [aws_security_group.elb.id]
   }

   ingress {
     description = "SSH"
     from_port   = 22
     to_port     = 22
     protocol    = "tcp"
     cidr_blocks = var.own_IP
   }

   egress {
     from_port   = 0
     to_port     = 0
     protocol    = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }

   tags = {
     Name = "allow_web"
  }
 }
# # 7. Create a network interface with an ip in the subnet that was created in step 4

resource "aws_network_interface" "web-server-nic" {
   subnet_id       = aws_subnet.subnet-public.id
   private_ips     = ["10.0.1.50", "10.0.1.51" , "10.0.1.52", "10.0.1.53","10.0.1.54","10.0.1.55"] #any Ip Adress of the subnet 
   security_groups = [aws_security_group.allow_web.id]

 }

# # 8. Assign an elastic IP to the network interface created in step 7

 resource "aws_eip" "one" {
   vpc                       = true
   network_interface         = aws_network_interface.web-server-nic.id
   associate_with_private_ip = "10.0.1.50" ##can put more than one 
   depends_on                = [aws_internet_gateway.gw] ##terraform don´t know it automatically 
 }

 output "server_public_ip" { #to test that EC2 is not directly accessable 
  value = aws_eip.one.public_ip
 }

# # 9. Create web server 

 resource "aws_launch_configuration" "web-server-instance" {
   image_id               = data.aws_ami.amazon-linux-2.id
   instance_type     = var.instance_type
   security_groups = [aws_security_group.allow_web.id]
   key_name          = "main-key"
   associate_public_ip_address = true


  user_data = <<-EOF
                 #!/bin/bash
                  yum update -y
                  yum install -y httpd.x86_64
                  systemctl start httpd.service
                  systemctl enable httpd.service
                  echo “Hello World from $(hostname -f)” > /var/www/html/index.html
                 EOF
  
   lifecycle {
    create_before_destroy = true
  }
 }

# # 10. ELB security group  
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb"
  vpc_id      =  aws_vpc.prod-vpc.id

  ingress {
     description = "HTTPS"
     from_port   = 443
     to_port     = 443
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"] 
   }

   ingress {
     description = "HTTP"
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

   tags = {
     Name = "ELB-SG"
  }
 }

# # 10. Create ELB 
resource "aws_elb" "example" {
  name               = "terraform-asg-example"
  security_groups    = [aws_security_group.elb.id]
  subnets = [aws_subnet.subnet-public.id]
  #availability_zones = data.aws_availability_zones.all.names
  #vpc_id      = aws_vpc.prod-vpc.id
  
  

   health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

# Add listener for incoming HTTP requests
  listener {
    lb_port           = var.elb_port
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
  }
}

# # 10. Create ASG

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.web-server-instance.id
  vpc_zone_identifier       = [aws_subnet.subnet-public.id]

  min_size = 2
  max_size = 5

  load_balancers    = [aws_elb.example.name]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

# put out dns name so we can test, if we can connect to ASG over the LB
output "clb_dns_name" {
  value       = aws_elb.example.dns_name
  description = "The domain name of the load balancer"
}

# # 11. Create simple Scaling for ASG based on cloudwatch metric
# scale up alarm
resource "aws_autoscaling_policy" "example-cpu-policy" {
name = "example-cpu-policy"
autoscaling_group_name = "${aws_autoscaling_group.example.name}"
adjustment_type = "ChangeInCapacity"
scaling_adjustment = "1"
cooldown = "300"
policy_type = "SimpleScaling"
}
resource "aws_cloudwatch_metric_alarm" "example-cpu-alarm" {
alarm_name = "example-cpu-alarm"
alarm_description = "example-cpu-alarm"
comparison_operator = "GreaterThanOrEqualToThreshold"
evaluation_periods = "2"
metric_name = "CPUUtilization"
namespace = "AWS/EC2"
period = "120"
statistic = "Average"
threshold = "70"
dimensions = {
"AutoScalingGroupName" = "${aws_autoscaling_group.example.name}"
}
actions_enabled = true
alarm_actions = ["${aws_autoscaling_policy.example-cpu-policy.arn}"]
}
# scale down alarm
resource "aws_autoscaling_policy" "example-cpu-policy-scaledown" {
name = "example-cpu-policy-scaledown"
autoscaling_group_name = "${aws_autoscaling_group.example.name}"
adjustment_type = "ChangeInCapacity"
scaling_adjustment = "-1"
cooldown = "300"
policy_type = "SimpleScaling"
}
resource "aws_cloudwatch_metric_alarm" "example-cpu-alarm-scaledown" {
alarm_name = "example-cpu-alarm-scaledown"
alarm_description = "example-cpu-alarm-scaledown"
comparison_operator = "LessThanOrEqualToThreshold"
evaluation_periods = "2"
metric_name = "CPUUtilization"
namespace = "AWS/EC2"
period = "120"
statistic = "Average"
threshold = "30"
dimensions = {
"AutoScalingGroupName" = "${aws_autoscaling_group.example.name}"
}
actions_enabled = true
alarm_actions = ["${aws_autoscaling_policy.example-cpu-policy-scaledown.arn}"]
}