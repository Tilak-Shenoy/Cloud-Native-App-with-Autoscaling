output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = aws_eks_cluster.eks-cloudapp.id
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.eks-cloudapp.arn
}

output "cluster_endpoint" {
  description = "The endpoint for the Kubernetes API server"
  value       = aws_eks_cluster.eks-cloudapp.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.eks-cloudapp.certificate_authority[0].data
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role that provides permissions for the Kubernetes control plane"
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role that provides permissions for the worker nodes"
  value       = aws_iam_role.nodes.arn
}

output "node_iam_role_name" {
  description = "Name of the IAM role that provides permissions for the worker nodes"
  value       = aws_iam_role.nodes.name
}

output "cluster_security_group_id" {
  description = "The security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_groups" {
  description = "Map of node group names to their ARNs"
  value = {
    for k, v in aws_eks_node_group.this : k => v.arn
  }
}
