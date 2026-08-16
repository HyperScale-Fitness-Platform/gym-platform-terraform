variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "The dynamic S3 bucket name where remote state files are stored"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "gym-cluster"
}

variable "infra_state_path" {
  description = "Relative path to Layer 1 (01-infrastructure) terraform.tfstate file"
  type        = string
  default     = "../infrastructure/terraform.tfstate"
}