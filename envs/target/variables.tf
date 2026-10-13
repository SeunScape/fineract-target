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

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "private_subnets" {
  description = "AZ suffix => CIDR."
  type        = map(string)
  default = {
    a = "10.20.1.0/24"
    b = "10.20.2.0/24"
  }
}

variable "bank_lan_cidr" {
  description = "Bank LAN behind the VPN (Droplet)."
  type        = string
  default     = "172.20.0.0/24"
}
