variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The environment (e.g., dev, staging, prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "The VPC ID where the EKS cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "node_groups" {
  description = "EKS node group configurations"
  type = map(object({
    instance_types = list(string)
    min_size      = number
    max_size      = number
    desired_size  = number
    capacity_type = string
    disk_size     = number
  }))
  default = {
    general = {
      instance_types = ["t3.medium"]
      min_size      = 1
      max_size      = 5
      desired_size  = 2
      capacity_type = "ON_DEMAND"
      disk_size     = 20
    }
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
