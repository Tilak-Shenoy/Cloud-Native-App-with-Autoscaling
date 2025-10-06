# Output values for other modules and external use

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_id" {
  description = "ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_port
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = module.alb.alb_dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = module.alb.alb_zone_id
}

# Security Group IDs
output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = module.security_groups.alb_sg_id
}

output "app_security_group_id" {
  description = "Security group ID for application"
  value       = module.security_groups.app_sg_id
}

output "database_security_group_id" {
  description = "Security group ID for database"
  value       = module.security_groups.database_sg_id
}

# Connection info for kubectl
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_id}"
}

# Database connection string (for application configuration)
output "database_url" {
  description = "Database connection URL"
  value       = "postgresql://${var.db_username}:${var.db_password}@${module.rds.db_endpoint}:${module.rds.db_port}/${var.db_name}"
  sensitive   = true
}
