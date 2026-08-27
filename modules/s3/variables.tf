variable "bucket_name" {
  type = string
}

variable "allowed_origins" {
  description = "Origins allowed to PUT/GET via CORS — the frontend's dev and prod URLs"
  type        = list(string)
}
