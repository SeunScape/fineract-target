provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "fineract-migration"
      env        = "target"
      phase      = var.phase
      managed-by = "terraform"
    }
  }
}
