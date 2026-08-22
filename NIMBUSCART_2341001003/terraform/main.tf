terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "NimbusCart"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------
# WEB VPC
# -----------------------------
resource "aws_vpc" "web" {
  cidr_block           = var.web_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-web-vpc" }
}

resource "aws_internet_gateway" "web" {
  vpc_id = aws_vpc.web.id
  tags   = { Name = "${var.project_name}-web-igw" }
}

resource "aws_subnet" "web" {
  vpc_id                  = aws_vpc.web.id
  cidr_block              = var.web_subnet_cidr
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-web-public-subnet", Tier = "web" }
}

resource "aws_route_table" "web_public" {
  vpc_id = aws_vpc.web.id
  tags   = { Name = "${var.project_name}-web-public-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web.id
  }

  route {
    cidr_block                = var.app_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.web_app.id
  }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.web_public.id
}

# -----------------------------
# APP VPC
# -----------------------------
resource "aws_vpc" "app" {
  cidr_block           = var.app_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-app-vpc" }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags   = { Name = "${var.project_name}-app-igw" }
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.app_subnet_cidr
  availability_zone = var.availability_zones[0]
  tags              = { Name = "${var.project_name}-app-private-subnet", Tier = "app" }
}

resource "aws_subnet" "nat" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.nat_subnet_cidr
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-nat-public-subnet", Tier = "app" }
}

resource "aws_route_table" "nat_public" {
  vpc_id = aws_vpc.app.id
  tags   = { Name = "${var.project_name}-nat-public-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

resource "aws_route_table_association" "nat" {
  subnet_id      = aws_subnet.nat.id
  route_table_id = aws_route_table.nat_public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.nat.id
  depends_on    = [aws_internet_gateway.app]
  tags          = { Name = "${var.project_name}-nat-gateway" }
}

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.app.id
  tags   = { Name = "${var.project_name}-app-private-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.app.id
  }

  route {
    cidr_block                = var.web_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.web_app.id
  }

  route {
    cidr_block                = var.data_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.app_data.id
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app_private.id
}

# -----------------------------
# DATA VPC
# -----------------------------
resource "aws_vpc" "data" {
  cidr_block           = var.data_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-data-vpc" }
}

resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.data.id
  cidr_block        = var.db_subnet_a_cidr
  availability_zone = var.availability_zones[0]
  tags              = { Name = "${var.project_name}-db-subnet-a", Tier = "db" }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.data.id
  cidr_block        = var.db_subnet_b_cidr
  availability_zone = var.availability_zones[1]
  tags              = { Name = "${var.project_name}-db-subnet-b", Tier = "db" }
}

resource "aws_route_table" "data_private" {
  vpc_id = aws_vpc.data.id
  tags   = { Name = "${var.project_name}-data-private-rt" }

  route {
    cidr_block                = var.app_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.app_data.id
  }
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.data_private.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.data_private.id
}

# -----------------------------
# VPC PEERING
# -----------------------------
resource "aws_vpc_peering_connection" "web_app" {
  vpc_id      = aws_vpc.web.id
  peer_vpc_id = aws_vpc.app.id
  auto_accept = true
  tags        = { Name = "${var.project_name}-web-app-peering" }
}

resource "aws_vpc_peering_connection" "app_data" {
  vpc_id      = aws_vpc.app.id
  peer_vpc_id = aws_vpc.data.id
  auto_accept = true
  tags        = { Name = "${var.project_name}-app-data-peering" }
}

# -----------------------------
# SECURITY GROUPS
# -----------------------------
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "HTTP and controlled SSH access to the Web tier"
  vpc_id      = aws_vpc.web.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from administrator CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Private API tier access"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "API from Web tier"
    from_port       = var.api_port
    to_port         = var.api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ingress {
    description     = "SSH through Web bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL only from App tier"
  vpc_id      = aws_vpc.data.id

  ingress {
    description     = "PostgreSQL from App tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# IAM FOR APP EC2 → ECR
# -----------------------------
resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_ecr" {
  name = "${var.project_name}-app-ecr-pull"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.api.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-instance-profile"
  role = aws_iam_role.app.name
}

# -----------------------------
# ECR
# -----------------------------
resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "null_resource" "image_build_push" {
  triggers = {
    api_source_hash = sha256(join("", [
      filesha256("${path.module}/../app/api/Dockerfile"),
      filesha256("${path.module}/../app/api/app.py"),
      filesha256("${path.module}/../app/api/requirements.txt")
    ]))
  }

  depends_on = [aws_ecr_repository.api]

  provisioner "local-exec" {
    working_dir = "${path.module}/../app/api"
    command = <<-EOT
      set -e
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.api.repository_url}
      docker build --platform linux/amd64 -t ${aws_ecr_repository.api.repository_url}:latest .
      docker push ${aws_ecr_repository.api.repository_url}:latest
    EOT
  }
}

# -----------------------------
# RDS POSTGRESQL
# -----------------------------
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]
  tags       = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  port                   = var.db_port
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
  deletion_protection    = false
  backup_retention_period = 1
  apply_immediately      = true
}

# -----------------------------
# EC2
# -----------------------------
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.web_instance_type
  subnet_id                   = aws_subnet.web.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-web-ec2"
    Tier = "web"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.app.name

  tags = {
    Name = "${var.project_name}-app-ec2"
    Tier = "app"
  }
}

# -----------------------------
# APP PROVISIONING
# Uses the Web EC2 as a bastion because the App EC2 has no public IP.
# -----------------------------
resource "null_resource" "app_provision" {
  triggers = {
    app_instance_id = aws_instance.app.id
    image_build     = null_resource.image_build_push.id
    db_endpoint     = aws_db_instance.postgres.address
  }

  depends_on = [
    aws_instance.web,
    aws_instance.app,
    aws_db_instance.postgres,
    null_resource.image_build_push,
    aws_vpc_peering_connection.web_app,
    aws_vpc_peering_connection.app_data,
    aws_route_table_association.app,
    aws_nat_gateway.app
  ]

  connection {
    type                = "ssh"
    host                = aws_instance.app.private_ip
    user                = "ubuntu"
    private_key         = file(var.private_key_path)
    timeout             = "10m"
    bastion_host        = aws_instance.web.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
  }

  provisioner "remote-exec" {
  inline = [
    "sudo cloud-init status --wait || true",
    "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo 'Waiting for dpkg lock...'; sleep 5; done",
    "sudo apt-get update -y",
    "sudo apt-get install -y docker.io netcat-openbsd unzip curl",
    "sudo systemctl enable --now docker",
    "if ! command -v aws >/dev/null 2>&1; then curl -s \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o /tmp/awscliv2.zip && cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install; fi",
    "until nc -z ${aws_db_instance.postgres.address} ${var.db_port}; do echo 'Waiting for RDS...'; sleep 5; done",
    "aws ecr get-login-password --region ${var.aws_region} | sudo docker login --username AWS --password-stdin ${aws_ecr_repository.api.repository_url}",
    "sudo docker pull ${aws_ecr_repository.api.repository_url}:latest",
    "sudo docker rm -f nimbuscart-api || true",
    "sudo docker run -d --name nimbuscart-api --restart unless-stopped -p ${var.api_port}:${var.api_port} -e DB_HOST=${aws_db_instance.postgres.address} -e DB_PORT=${var.db_port} -e DB_NAME=${var.db_name} -e DB_USER=${var.db_username} -e DB_PASSWORD=$(printf %s '${base64encode(var.db_password)}' | base64 -d) ${aws_ecr_repository.api.repository_url}:latest"
  ]
}
}

# -----------------------------
# WEB PROVISIONING
# file + remote-exec are deliberately separated from the instance resource
# to avoid a dependency cycle: App provisioning uses Web as an SSH bastion.
# -----------------------------
resource "null_resource" "web_provision" {
  triggers = {
    web_instance_id = aws_instance.web.id
    app_private_ip  = aws_instance.app.private_ip
  }

  depends_on = [null_resource.app_provision]

  connection {
    type        = "ssh"
    host        = aws_instance.web.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    timeout     = "10m"
  }

  provisioner "file" {
    source      = "${path.module}/../app/frontend/index.html"
    destination = "/tmp/index.html"
  }

  provisioner "file" {
    content = <<-NGINX
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          server_name _;

          root /var/www/nimbuscart;
          index index.html;

          location / {
              try_files $uri $uri/ /index.html;
          }

          location /api/ {
              proxy_pass http://${aws_instance.app.private_ip}:${var.api_port};
              proxy_http_version 1.1;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          }
      }
    NGINX
    destination = "/tmp/nimbuscart.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx",
      "sudo mkdir -p /var/www/nimbuscart",
      "sudo mv /tmp/index.html /var/www/nimbuscart/index.html",
      "sudo mv /tmp/nimbuscart.conf /etc/nginx/sites-available/nimbuscart",
      "sudo rm -f /etc/nginx/sites-enabled/default",
      "sudo ln -sf /etc/nginx/sites-available/nimbuscart /etc/nginx/sites-enabled/nimbuscart",
      "sudo nginx -t",
      "sudo systemctl enable --now nginx",
      "sudo systemctl restart nginx"
    ]
  }
}
