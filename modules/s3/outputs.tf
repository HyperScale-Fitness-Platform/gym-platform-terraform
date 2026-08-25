output "bucket_name" {
  value = aws_s3_bucket.product_images.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.product_images.arn
}

output "bucket_regional_domain_name" {
  value = aws_s3_bucket.product_images.bucket_regional_domain_name
}
