# 1. Menentukan Provider (Kita memberitahu Terraform bahwa kita pakai AWS, di Region Singapura)
provider "aws" {
  region = "ap-southeast-1"
}

# 2. Membuat VPC (Virtual Private Cloud)
# Analogi: Ini adalah Gedung Data Center baru Anda. Kita beri blok IP besar.
resource "aws_vpc" "primary_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  
  tags = {
    Name = "Skripsi-VPC-RegionA"
  }
}

# 3. Membuat Subnet Public
# Analogi: Ini adalah Switch / VLAN tempat server kita akan dicolok nanti.
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # Server di sini otomatis dapat IP Public
  availability_zone       = "ap-southeast-1a"
  
  tags = {
    Name = "Skripsi-PublicSubnet-A"
  }
}

# 4. Membuat Internet Gateway (IGW)
# Analogi: Ini adalah Edge Router yang menyambungkan Data Center kita ke ISP / Internet luar.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.primary_vpc.id

  tags = {
    Name = "Skripsi-IGW-A"
  }
}

# 5. Membuat Route Table dan menghubungkannya ke Subnet
# Analogi: Seperti perintah "ip route 0.0.0.0 0.0.0.0 <IP_IGW>" di router Cisco.
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.primary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. Security Group (Firewall)
# Analogi: Ini seperti Access Control List (ACL) / Firewall fisik. 
# Kita izinkan traffic HTTP (Port 80) dari mana saja, dan SSH (Port 22) untuk akses remote.
resource "aws_security_group" "web_sg" {
  name        = "skripsi-web-sg"
  description = "Izinkan trafik HTTP dan SSH"
  vpc_id      = aws_vpc.primary_vpc.id

  # Inbound Rule: Izinkan HTTP dari mana saja
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound Rule: Izinkan SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rule: Izinkan server keluar ke internet (misal untuk download package)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Skripsi-WebSG-A"
  }
}

# 7. Mencari AMI Ubuntu Terbaru secara Otomatis
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 8. Deploy Server EC2 (Monolith App)
# Analogi: Ini adalah Server Rack / PC Server fisik Anda.
resource "aws_instance" "web_server" {
  ami                   = data.aws_ami.ubuntu.id
  instance_type         = "t3.micro" # Tipe hemat/Free Tier
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # User Data: Skrip shell otomatis untuk install Web Server NGINX saat server booting pertama kali
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>[REGION A - PRIMARY] Web Server Monolitik Skripsi Active!</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "Skripsi-WebServer-RegionA"
  }
}

# Output: Menampilkan IP Public Server di terminal setelah deploy selesai
output "web_server_public_ip" {
  value       = "http://${aws_instance.web_server.public_ip}"
  description = "Akses URL Web Server Region A di Browser Anda"
}