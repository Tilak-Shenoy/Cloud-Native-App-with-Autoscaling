# Main Terraform configuration for Cloud-Native App Infrastructure
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local values
locals {
  cluster_name = "${var.project_name}-${var.environment}"
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  project_name     = var.project_name
  environment      = var.environment
  vpc_cidr         = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  
  tags = local.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security-groups"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
  
  tags = local.common_tags
}

# RDS Module
module "rds" {
  source = "./modules/rds"
  
  project_name           = var.project_name
  environment            = var.environment
  db_instance_class      = var.db_instance_class
  db_allocated_storage   = var.db_allocated_storage
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  database_security_group_id = module.security_groups.database_sg_id
  
  tags = local.common_tags
}

# EKS Module
module "eks" {
  source = "./modules/eks"
  
  project_name        = var.project_name
  environment         = var.environment
  cluster_version     = var.cluster_version
  
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  
  node_groups = var.node_groups
  
  tags = local.common_tags
}

# Application Load Balancer
module "alb" {
  source = "./modules/alb"
  
  project_name    = var.project_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_sg_id
  
  tags = local.common_tags
}
