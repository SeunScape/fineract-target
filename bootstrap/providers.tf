provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "fineract-migration"
      env        = "target"
      phase      = "2"
      managed-by = "terraform"
      layer      = "bootstrap"
    }
  }
}
