output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "alb_controller_role_arn" {
  value = module.irsa_roles.alb_controller_role_arn
}

output "external_secrets_role_arn" {
  value = module.irsa_roles.external_secrets_role_arn
}

output "ecr_repository_urls" {
  value = { for k, v in module.ecr.repository_urls : k => v }
}