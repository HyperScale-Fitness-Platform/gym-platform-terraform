terraform {
  backend "local" {
    path = "../infrastructure/terraform.tfstate"
  }
}