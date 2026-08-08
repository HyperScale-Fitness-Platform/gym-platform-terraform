terraform {
  backend "local" {
    path = "../01-infrastructure/terraform.tfstate"
  }
}