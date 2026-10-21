# EC2-only primary workload: no Amazon EKS, ALB, or Kubernetes.
# Before terraform apply on an existing lab, read docs/MIGRATION.md.
provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_vpc" "primary_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "Skripsi-VPC-RegionA" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Skripsi-PublicSubnet-A" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.primary_vpc.id
  tags   = { Name = "Skripsi-IGW-A" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.primary_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_rt_assoc_1" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  name        = "skripsi-web-sg"
  description = "Lab primary HTTP only; SSH not exposed"
  vpc_id      = aws_vpc.primary_vpc.id
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
  tags = { Name = "Skripsi-WebSG-A" }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Create a FRESH primary EC2 to guarantee user_data runs on first launch.
resource "aws_instance" "primary_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
    mkdir -p /var/www/html
    echo '${base64encode(file("${path.module}/app/index.html"))}' | base64 -d > /var/www/html/index.html
    printf 'ready\n' > /var/www/html/healthz
    printf 'add_header X-DR-Region "region-a" always;\n' > /etc/nginx/conf.d/dr-region.conf
    systemctl enable nginx
    systemctl restart nginx
  USERDATA

  tags = { Name = "Skripsi-WebServer-RegionA" }
}

# Stable Route 53 target; public IPv4 costs still apply (even with stopped EC2).
resource "aws_eip" "primary_static_ip" {
  domain   = "vpc"
  instance = aws_instance.primary_ec2.id
  tags     = { Name = "Skripsi-Primary-EC2-IP" }
}

output "web_server_public_ip" {
  value       = "http://${aws_eip.primary_static_ip.public_ip}"
  description = "Primary EC2 HTTP endpoint (not EKS)."
}

output "region_a_eip" {
  value = aws_eip.primary_static_ip.public_ip
}

output "region_a_instance_id" {
  value = aws_instance.primary_ec2.id
}
