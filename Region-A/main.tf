# ==========================================
# INFRASTRUKTUR DASAR (VPC, SUBNET, ROUTING)
# ==========================================

# 1. Menentukan Provider
provider "aws" {
  region = "ap-southeast-1"
}

# 2. Membuat VPC (Virtual Private Cloud)
resource "aws_vpc" "primary_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  
  tags = {
    Name = "Skripsi-VPC-RegionA"
  }
}

# 3a. Membuat Subnet Public Pertama (Zona A)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true 
  availability_zone       = "ap-southeast-1a"
  
  tags = {
    Name = "Skripsi-PublicSubnet-A"
  }
}

# 3b. Membuat Subnet Public Kedua (Zona B) - Syarat Wajib EKS
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.2.0/24" 
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-1b" 
  
  tags = {
    Name = "Skripsi-PublicSubnet-A2"
  }
}

# 4. Membuat Internet Gateway (IGW)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.primary_vpc.id

  tags = {
    Name = "Skripsi-IGW-A"
  }
}

# 5. Membuat Route Table dan menghubungkannya ke Kedua Subnet
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

resource "aws_route_table_association" "public_rt_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. Security Group (Firewall)
resource "aws_security_group" "web_sg" {
  name        = "skripsi-web-sg"
  description = "Izinkan trafik HTTP dan SSH"
  vpc_id      = aws_vpc.primary_vpc.id

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
    Name = "Skripsi-WebSG-A"
  }
}

# ==========================================
# SERVER BASELINE (EC2 MONOLITIK)
# ==========================================

# 7. Mencari AMI Ubuntu Terbaru 
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 8. Deploy Server EC2 (Pembanding Manual DR)
resource "aws_instance" "web_server" {
  ami                   = data.aws_ami.ubuntu.id
  instance_type         = "t3.micro" 
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

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

output "web_server_public_ip" {
  value       = "http://${aws_instance.web_server.public_ip}"
  description = "Akses URL Web Server Region A di Browser Anda"
}

# ==========================================
# ELASTIC KUBERNETES SERVICE (EKS) 
# ==========================================

# 9. IAM Role untuk AWS EKS Cluster (Control Plane)
resource "aws_iam_role" "eks_cluster_role" {
  name = "skripsi-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# 10. EKS Cluster (Menggunakan 2 Subnet Lintas AZ)
resource "aws_eks_cluster" "primary_eks" {
  name     = "skripsi-eks-region-a"
  role_arn = aws_iam_role.eks_cluster_role.arn
  vpc_config {
    subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id] 
  }
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# 11. IAM Role untuk EKS Node Group (Worker Nodes)
resource "aws_iam_role" "eks_node_role" {
  name = "skripsi-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# 12. EKS Node Group (Menggunakan 2 Subnet Lintas AZ)
resource "aws_eks_node_group" "node_group_a" {
  cluster_name    = aws_eks_cluster.primary_eks.name
  node_group_name = "skripsi-nodes-a"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["t3.small"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry,
  ]
}