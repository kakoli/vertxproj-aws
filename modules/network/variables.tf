variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "RDS needs private subnets in at least 2 availability zones."
  }
}

variable "app_port" {
  type = number
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "allowed_app_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.allowed_app_cidrs) > 0
    error_message = "allowed_app_cidrs must not be empty."
  }
}

variable "allowed_ssh_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.allowed_ssh_cidrs) > 0
    error_message = "allowed_ssh_cidrs must not be empty."
  }
}
