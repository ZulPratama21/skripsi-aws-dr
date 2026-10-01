terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 1. Provider AWS (Region B: Tokyo / ap-northeast-1)
provider "aws" {
  region = "ap-northeast-1"
}

# 2. VPC Region B
resource "aws_vpc" "secondary_vpc" {
  cidr_block           = "10.1.0.0/16" # Blok IP beda agar tidak konflik dengan Region A (10.0.0.0/16)
  enable_dns_hostnames = true
  
  tags = {
    Name = "Skripsi-VPC-RegionB"
  }
}

# 3. Subnet Public Region B
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
  
  tags = {
    Name = "Skripsi-PublicSubnet-B"
  }
}

# 4. Internet Gateway Region B
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.secondary_vpc.id

  tags = {
    Name = "Skripsi-IGW-B"
  }
}

# 5. Route Table Region B
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.secondary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Skripsi-PublicRT-B"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. Security Group (Firewall) Region B
resource "aws_security_group" "web_sg" {
  name        = "skripsi-web-sg-b"
  description = "Izinkan trafik HTTP dan SSH"
  vpc_id      = aws_vpc.secondary_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "Skripsi-WebSG-B"
  }
}

# 7. Mencari AMI Ubuntu Terbaru di Tokyo
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 7b. Membuat SSH Key Pair secara dinamis untuk akses Ansible
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "region_b_key" {
  key_name   = "skripsi-ansible-key-b"
  public_key = tls_private_key.ansible_key.public_key_openssh
}

# 8. Server EC2 Region B (Pilot Light - Server OS Kosong)
resource "aws_instance" "web_server_b" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  # Memasang "Gembok" (Public Key) ke server ini
  key_name               = aws_key_pair.region_b_key.key_name

  # Skrip user_data DIHAPUS. Server akan standby dalam keadaan kosong.

  tags = {
    Name = "Skripsi-WebServer-RegionB-Standby"
  }
}

# Output URL Region B
output "web_server_b_public_ip" {
  value       = "http://${aws_instance.web_server_b.public_ip}"
  description = "Akses URL Web Server Region B di Browser Anda"
}

# Output Private Key (Kunci ini akan kita simpan di GitHub Secrets untuk Ansible)
output "ansible_private_key" {
  value       = tls_private_key.ansible_key.private_key_pem
  sensitive   = true
  description = "Private Key SSH untuk Ansible"
}