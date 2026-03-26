terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ----------- VPC -----------
resource "aws_vpc" "novamart" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "novamart-vpc", Project = "novamart-migration", Phase = "replatform" }
}

resource "aws_internet_gateway" "novamart" {
  vpc_id = aws_vpc.novamart.id
  tags   = { Name = "novamart-igw" }
}

# Two public subnets (required for ALB)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.novamart.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "novamart-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.novamart.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "novamart-public-b" }
}

# Two private subnets for RDS
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.novamart.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "novamart-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.novamart.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "novamart-private-b" }
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.novamart.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.novamart.id
  }
  tags = { Name = "novamart-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ----------- Security Groups -----------
resource "aws_security_group" "alb" {
  name_prefix = "novamart-alb-"
  vpc_id      = aws_vpc.novamart.id
  description = "ALB security group - accepts HTTP from internet"

  ingress {
    description = "HTTP from anywhere"
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

  tags = { Name = "novamart-alb-sg" }
}

resource "aws_security_group" "app" {
  name_prefix = "novamart-app-"
  vpc_id      = aws_vpc.novamart.id
  description = "App security group - accepts traffic from ALB only"

  ingress {
    description     = "App port from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH (restrict in production)"
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

  tags = { Name = "novamart-app-sg" }
}

resource "aws_security_group" "rds" {
  name_prefix = "novamart-rds-"
  vpc_id      = aws_vpc.novamart.id
  description = "RDS security group - accepts connections from app servers only"

  ingress {
    description     = "PostgreSQL from app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "novamart-rds-sg" }
}

# ----------- RDS PostgreSQL -----------
resource "aws_db_subnet_group" "novamart" {
  name       = "novamart-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = { Name = "novamart-db-subnet-group" }
}

resource "aws_db_instance" "novamart" {
  identifier              = "novamart-inventory-db"
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = "novamart"
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.novamart.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  skip_final_snapshot     = true
  backup_retention_period = 7
  # multi_az              = true  # Uncomment for production (adds ~$30/mo)

  tags = {
    Name    = "novamart-inventory-db"
    Project = "novamart-migration"
    Phase   = "replatform"
  }
}

# ----------- Application Load Balancer -----------
resource "aws_lb" "novamart" {
  name               = "novamart-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "novamart-alb", Project = "novamart-migration" }
}

resource "aws_lb_target_group" "novamart" {
  name     = "novamart-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.novamart.id

  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "novamart-tg" }
}

resource "aws_lb_listener" "novamart" {
  load_balancer_arn = aws_lb.novamart.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.novamart.arn
  }
}

# ----------- Launch Template + ASG -----------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "novamart" {
  name_prefix   = "novamart-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/../scripts/userdata.sh", {
    db_host     = aws_db_instance.novamart.address
    db_port     = aws_db_instance.novamart.port
    db_name     = aws_db_instance.novamart.db_name
    db_username = var.db_username
    db_password = var.db_password
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "novamart-app-server"
      Project = "novamart-migration"
      Phase   = "replatform"
    }
  }
}

resource "aws_autoscaling_group" "novamart" {
  name                = "novamart-asg"
  desired_capacity    = 2
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  target_group_arns   = [aws_lb_target_group.novamart.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.novamart.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "novamart-app-server"
    propagate_at_launch = true
  }
}
