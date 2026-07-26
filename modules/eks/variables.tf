variable "cluster_name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "private_subnets" {
  type = list(string)
}
variable "public_subnets" {
  type = list(string)
}
variable "node_instance_type" {
  type    = string
  default = "m7i-flex.large"
}