output "cluster_name" {
  value = module.eks.cluster_name
}
output "ecr_repository_urls" {
  value = { for k, v in module.ecr.repository_urls : k => v }
}
output "auth_rds_endpoint" {
  value = module.auth_rds.endpoint
}