output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}
output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}
output "ebs_csi_role_arn" {
  value = module.ebs_csi_irsa_role.iam_role_arn
}
output "image_updater_iam_role_arn" {
  value = aws_iam_role.image_updater.arn
}
output "gateway_s3_role_arn" {
  description = "IAM Role ARN for api-gateway to assume via IRSA for S3 presigned uploads"
  value       = module.irsa_roles.gateway_s3_role_arn
}

output "product_images_bucket_name" {
  description = "S3 bucket name for product images"
  value       = module.product_images_bucket.bucket_name
}
