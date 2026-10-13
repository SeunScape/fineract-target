variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "phase" {
  type    = string
  default = "2"
}

variable "enable_vpn" {
  type    = bool
  default = false
}

variable "enable_rds" {
  type    = bool
  default = false
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "source_public_ip" {
  description = "Public IPv4 of the Droplet (VPN customer gateway)."
  type        = string

  validation {
    condition     = can(cidrhost("${var.source_public_ip}/32", 0))
    error_message = "source_public_ip must be an IPv4 address."
  }
}
