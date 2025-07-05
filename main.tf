# AWS Provider 설정 (us-east-1은 버지니아 리전)
provider "aws" {
  region = var.aws_region
}

# -----------------------------------------
# 네트워크: VPC + Public / Private Subnets
# -----------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.250.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.cluster_name}-vpc"
    Environment = "dev"
    Owner       = "terraform"
  }
}

# 퍼블릭 서브넷 (Bastion 전용)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.250.1.0/24"
  map_public_ip_on_launch = false # EIP를 명시적으로 연결함
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name        = "${var.cluster_name}-public-subnet"
    Role        = "public"
    Environment = "dev"
  }
}

# 프라이빗 서브넷 (K8s Master/Worker 전용)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.250.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.cluster_name}-private-subnet"
    Role        = "private"
    Environment = "dev"
  }
}

# 인터넷 게이트웨이 연결 (퍼블릭 서브넷에서 외부로 나갈 수 있게)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# 퍼블릭 서브넷용 라우트 테이블
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# 라우팅 테이블 → 퍼블릭 서브넷 연결
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------
# 보안 그룹 (SSH + 내부 통신)
# -----------------------------------------

# 내 PC에서 Bastion으로 SSH 허용 (22번 포트만 열림)
resource "aws_security_group" "bastion_sg" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Allow SSH from my IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-bastion-sg"
  }
}

# Bastion에서 Master/Worker로 SSH 및 K8s 포트 통신 허용
resource "aws_security_group" "internal_sg" {
  name        = "${var.cluster_name}-internal-sg"
  description = "Allow internal SSH and Kubernetes ports"
  vpc_id      = aws_vpc.main.id

  # Bastion → Master/Worker: SSH
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Bastin -> kube-apiserver
  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Bastion -> kubelet
  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Master -> etcd
  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
  }

  # Master → scheduler
  ingress {
    from_port = 10259
    to_port   = 10259
    protocol  = "tcp"
    self      = true
  }

  # Master → controller-manager
  ingress {
    from_port = 10257
    to_port   = 10257
    protocol  = "tcp"
    self      = true
  }

  # Worker → kube-proxy
  ingress {
    from_port = 10256
    to_port   = 10256
    protocol  = "tcp"
    self      = true
  }

  # NodePort 서비스용 포트
  ingress {
    from_port = 30000
    to_port   = 32767
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 30000
    to_port   = 32767
    protocol  = "udp"
    self      = true
  }

  # Calico BGP (IP-in-IP가 아닌 BGP로 통신 시 필요)
  ingress {
    from_port = 179
    to_port   = 179
    protocol  = "tcp"
    self      = true
  }

  # Calico VXLAN (기본적으로 사용됨, IPIP일 경우 제외)
  ingress {
    from_port = 4789
    to_port   = 4789
    protocol  = "udp"
    self      = true
  }

  # Master/Worker 간 내부 통신
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-internal-sg"
  }
}

# -----------------------------------------
# Ubuntu AMI ( Ubuntu 22.04)
# -----------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }
}

# -----------------------------------------
# Bastion Host (퍼블릭 IP 없음 + EIP 연결)
# -----------------------------------------
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = false # EIP로 연결
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "${var.cluster_name}-bastion"
    Role = "bastion"
  }
}

# Bastion에 Elastic IP 할당
resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id

  tags = {
    Name        = "${var.cluster_name}-bastion-eip"
    Role        = "bastion"
    Environment = "dev"
    Owner       = "terraform"
  }
}

# -----------------------------------------
# Kubernetes Master 노드 (Private Subnet)
# -----------------------------------------
resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.master_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.internal_sg.id]

  tags = {
    Name = "${var.cluster_name}-master"
    Role = "k8s-master"
  }
}

# Kubernetes Worker 노드 (Private Subnet)
resource "aws_instance" "worker" {
  count                       = 2
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.internal_sg.id]

  tags = {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    Role = "k8s-worker"
  }
}


# -----------------------------------------
# NAT 추가 
# -----------------------------------------
# NAT Gateway용 EIP
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name        = "${var.cluster_name}-nat-eip"
    Environment = "dev"
    Owner       = "terraform"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id      # 퍼블릭 서브넷에 NAT Gateway를 둬야 함
  depends_on    = [aws_internet_gateway.gw] # IGW 먼저 생성돼야 NAT 가능

  tags = {
    Name = "${var.cluster_name}-nat-gateway"
  }
}

# Private Subnet용 라우팅 테이블
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

# Private Subnet과 라우팅 테이블 연결
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
