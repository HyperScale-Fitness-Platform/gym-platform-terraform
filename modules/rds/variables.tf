variable "service_name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "private_subnets" {
  type = list(string)
}
variable "node_security_group_id" {
  type = string
}
variable "db_name" {
  type = string
}