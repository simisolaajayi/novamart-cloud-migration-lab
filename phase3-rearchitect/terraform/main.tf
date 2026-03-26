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

# ---------------------------------------------------------------------------
# NOTE: If you already have an EKS cluster from the cloud-migration-infra lab,
# you can skip this Terraform entirely and deploy directly to that cluster.
#
# To use your existing cluster:
#   aws eks update-kubeconfig --name migration-eks-cluster --region us-east-1
#   kubectl apply -f kubernetes/
#
# The Terraform below creates a NEW, standalone EKS cluster for this lab.
# ---------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "novamart-eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Project = "novamart-migration"
    Phase   = "rearchitect"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    novamart_nodes = {
      instance_types = [var.node_instance_type]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      labels = {
        project = "novamart-migration"
      }
    }
  }

  tags = {
    Project = "novamart-migration"
    Phase   = "rearchitect"
  }
}
