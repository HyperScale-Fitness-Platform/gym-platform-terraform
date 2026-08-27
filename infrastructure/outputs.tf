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

output "gateway_s3_role_arn" {
  description = "IAM Role ARN for api-gateway IRSA (S3 presigned uploads)"
  value       = module.irsa_roles.gateway_s3_role_arn
}

output "product_images_bucket_name" {
  description = "S3 bucket name for product images"
  value       = module.product_images_bucket.bucket_name
}

output "product_images_bucket_arn" {
  description = "S3 bucket ARN for product images"
  value       = module.product_images_bucket.bucket_arn
}

output "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS cluster OIDC provider URL"
  value       = module.eks.oidc_provider_url
}