# Building a Production-Grade Site Reliability Engineering (SRE) Monitoring Stack on AWS with Terraform, Docker, and Grafana

## Overview
- As a DevOps and SRE enthusiast I recently completed a hands-on infrastructure monitoring project that brings together the power of AWS, Terraform, Docker, and Grafana to monitor the health and reliability of web services running behind an Application Load Balancer (ALB).

## Stack Overview
- AWS EC2 for hosting Prometheus and Grafana.
- Application Load Balancer(ALB) in front of backend targets.
- Docker Compose for deploying Prometheus and Grafana.
- CloudWatch Metrics integration.
- Terraform to provision all AWS infrastructure.
- GitHub Actions CI/CD for automated Terraform workflows.
-Grafana Dashboards visualizing ELB performance and health.

## project Structure
aws-sre-monitoring-stack/
├── .github/
│   └── workflows/
│       └── terraform.yml
├── prometheus_grafana/
│   ├── docker-compose.yml
│   └── prometheus.yml
├── terraform/
│   ├── alb.tf
│   ├── cloudwatch.tf
│   ├── ec2.tf
│   ├── outputs.tf
│   ├── sns.tf
│   └── vpc.tf
├── .gitignore
└── README.md

## Infrastructure-as-Code with Terraform
Everything in this project is built using Terraform
- vpc: Creating an isolated network.
### vpc.tf
```
# VPC

provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "sre-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

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

resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = aws_vpc.main.id

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

```

- ec2: Launching monitoring instances.

### ec2.tf
```
# Launch Template

resource "aws_launch_template" "app" {
  name_prefix   = "sre-app"
  image_id      = "ami-084568db4383264d4"
  instance_type = "t2.micro"

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

```
- alb: Setting up the Application Load Balancer and it's target group.
### alb.tf
```
# ALB
resource "aws_lb" "app" {
  name               = "sre-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "tg" {
  name     = "sre-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

```
- cloudwatch: setting alarms for CPU usage and ELB Errors.
### cloudwatch.tf
```
# CloudWatch Alarm (CPU > 70%)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "HighCPUUsage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 50
  alarm_description   = "Triggers when CPU > 50%"
  alarm_actions       = [aws_sns_topic.terminator.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

```
- sns: sending alert notifiactions. 
### sns.tf
```
# SNS Alerts
resource "aws_sns_topic" "terminator" {
  name = "sre-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.terminator.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

```

## Monitoring Stack with Prometheus + Grafana
Prometheus and Grafana were deployed using Docker Compose on an EC@ instance.

### docker-compose.yml
```
version: '3'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana-storage:/var/lib/grafana
    restart: always

volumes:
  grafana-storage:
```
### prometheus.yml
```
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'Prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'EC2'
    static_configs:
      - targets:
          - '18.xxx.xxx.238:9100'
          - '34.xxx.xxx.64:9100'
```

### Metrics Monitored in Grafana
Using Grafana's cloud watch data source create custom dashboards for:
- TargetResponseTime - Latency from ALB to targets.
- RequestCountPerTarget - load distribution insights.
- HTTPCode_ELB_5XX_count - critical ELB errors
- RequestCount - overall traffic hitting the application.

## CI/CD Automation with GitHub Actions (Terraform + Docker)
This project includes a multi-stage CI/CD pipeline built using GitHub Actions. The pipeline has two jobs:
1. Terraform workflow:- initializes, formats, validates and plans infrastructure
2. Docker workflow:- Deploys the monitoring stack using Docker Compose after Terraform completes.

### terraform.yml
```
name: Terraform

on:
  push:
    branches:
      - main

jobs:
  terraform:
    name: Terraform Workflow
    runs-on: ubuntu-latest
    
    # 🌟 This forces ALL steps in this job to run inside the terraform directory
    defaults:
      run:
        working-directory: ./terraform

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.15.5

      - name: Terraform Init
        run: terraform init
        env:
          TF_TOKEN_app_terraform_io: ${{ secrets.TF_TOKEN_app_terraform_io }}
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Terraform Format (Auto-Fix)
        run: terraform fmt -recursive

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan -no-color
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          TF_TOKEN_app_terraform_io: ${{ secrets.TF_TOKEN_app_terraform_io }}

  Docker:
    needs: terraform
    name: Deploy Docker Compose
    runs-on: ubuntu-latest
    
    # 🌟 Do the same for the Docker job to point to your monitoring folder
    defaults:
      run:
        working-directory: ./prometheus_grafana

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Setup Docker
        uses: docker/setup-docker-action@v4

      - name: Set up Docker Compose
        uses: docker/setup-compose-action@v1

      - name: Deploy Compose file
        run: docker compose up -d

      - name: Deploy Successfully
        run: echo "deployed"
```

## Why This Matters
- Terraform job ensure infrastructure is formatted, validated and securely deployed.
- Docker job launches Prometheus and Grafana using Docker Compose on success.
- Uses GitHub secrets to inject AWS and terraform credentials securely.
- CI/CD workflow enables zero-touch deployments from code push to cloud and monitoring.
- This pipeline makes the project enterprise-grade with infrastructure-as-code and monitoring-as-code fully automated.

## CloudWatch Insights
Real-time metrics visualized via cloudWatch include
- TargetResponseTime - shows spikes around 12:40PM.
- HTTPCode_Target_5XX_Count - used to catch ELB internal errors.
- RequestCount - tracks application traffic.

## Alarm Setup
I configured a cloudWatch alarm for CPU usage
```
alarm_name = "HighCPUUsage"
metric_name = "CPUUtilization"
threshold = 50
```
The alarm triggers an SNS topic that notifies my email

## Top 3 ELB Metrics to monitor
1. HTTPCode_ELB_5XX_Count critical to identify internal load balancer issues.
2. TargetResponseTime Measures app latency and perforance.
3. RequestCountPertarget Ensures proper traffic distribution across services
