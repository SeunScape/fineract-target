terraform {
  backend "s3" {
    bucket       = "fineract-target-tfstate-755431180020"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    kms_key_id   = "alias/fineract-target"
    use_lockfile = true
  }
}
