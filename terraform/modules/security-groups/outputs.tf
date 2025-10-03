output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "ID of the application security group"
  value       = aws_security_group.app.id
}

output "database_sg_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster security group"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_sg_id" {
  description = "ID of the EKS nodes security group"
  value       = aws_security_group.eks_nodes.id
}

output "bastion_sg_id" {
  description = "ID of the bastion security group"
  value       = aws_security_group.bastion.id
}
