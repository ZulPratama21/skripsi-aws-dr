terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_vpc" "secondary_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "Skripsi-VPC-RegionB" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Skripsi-PublicSubnet-B" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.secondary_vpc.id
  tags   = { Name = "Skripsi-IGW-B" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.secondary_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Skripsi-PublicRT-B" }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  name        = "skripsi-web-sg-b"
  description = "Secondary HTTP, temporary runner SSH ingress only"
  vpc_id      = aws_vpc.secondary_vpc.id
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
  tags = { Name = "Skripsi-WebSG-B" }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# LEGACY COMPATIBILITY. Private key is stored in Terraform state.
# A future migration should import an externally generated public key instead.
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "region_b_key" {
  key_name   = "skripsi-ansible-key-b"
  public_key = tls_private_key.ansible_key.public_key_openssh
}

# Pre-provisioned EC2. After initial setup, STOP this instance between trials.
# On first boot nginx package is installed but service remains DISABLED.
resource "aws_instance" "web_server_b" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.region_b_key.key_name

  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
    systemctl disable --now nginx
  USERDATA

  tags = { Name = "Skripsi-WebServer-RegionB-Standby" }
}

# Keep endpoint stable across stop/start. EIP has a monthly cost while unused.
resource "aws_eip" "secondary_static_ip" {
  domain   = "vpc"
  instance = aws_instance.web_server_b.id
  tags     = { Name = "Skripsi-RegionB-DR-ElasticIP" }
}

output "web_server_b_public_ip" {
  value = "http://${aws_eip.secondary_static_ip.public_ip}"
}

output "region_b_eip" {
  value = aws_eip.secondary_static_ip.public_ip
}

output "region_b_instance_id" {
  value = aws_instance.web_server_b.id
}

output "region_b_security_group_id" {
  value = aws_security_group.web_sg.id
}

output "ansible_private_key" {
  value       = tls_private_key.ansible_key.private_key_openssh
  sensitive   = true
  description = "Legacy lab secret; handle Terraform state as confidential."
}
