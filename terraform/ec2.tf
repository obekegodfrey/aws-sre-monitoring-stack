# Launch Template

resource "aws_launch_template" "app" {
  name_prefix   = "sre-app"
  image_id      = "ami-091138d0f0d41ff90"
  instance_type = "t3.micro"

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update
              apt install -y apache2
              systemctl start apache2
              echo "Hello from $(hostname)" > /var/www/html/index.html
              EOF
            )

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public[*].id

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]

  tag {
    key                 = "Name"
    value               = "sre-instance"
    propagate_at_launch = true
  }
}
