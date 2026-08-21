output "cluster_name" {
  description = "EKS cluster name used by services providers"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint URL used by services providers"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required for K8s/Helm authentication"
  value       = module.eks.cluster_certificate_authority_data
}

output "image_updater_iam_role_arn" {
  description = "IAM Role ARN for Argo CD Image Updater"
  value       = module.irsa_roles.image_updater_iam_role_arn
}