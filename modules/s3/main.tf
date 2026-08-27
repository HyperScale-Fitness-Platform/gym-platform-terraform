resource "aws_s3_bucket" "product_images" {
  bucket        = var.bucket_name
  force_destroy = true # hobby project — allow terraform destroy to actually remove it
}

# Images are served straight to <img> tags in the frontend, so reads are
# public. Writes are never public — the only way to write is a short-lived
# presigned PUT URL issued by the gateway (see modules/irsa-roles).
resource "aws_s3_bucket_public_access_block" "product_images" {
  bucket = aws_s3_bucket.product_images.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.product_images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadProductImages"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.product_images.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.product_images]
}

# Needed so the browser (not a backend) can PUT directly to S3 using the
# gateway's presigned URL — without this, the browser's preflight OPTIONS
# request gets rejected before the PUT ever happens.
resource "aws_s3_bucket_cors_configuration" "product_images" {
  bucket = aws_s3_bucket.product_images.id

  cors_rule {
    allowed_methods = ["PUT", "GET"]
    allowed_origins = var.allowed_origins
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}
