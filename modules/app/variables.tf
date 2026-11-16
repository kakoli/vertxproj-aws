variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_id" {
  description = "Public subnet for the instance."
  type        = string
}

variable "security_group_id" {
  description = "App security group from the network module."
  type        = string
}

variable "instance_type" {
  type    = string
}

variable "ami_architecture" {
  type    = string
}

variable "root_volume_gb" {
  type    = number
}

variable "ssh_public_key_path" {
  type = string
}

variable "ssh_private_key_path" {
  type = string
}

variable "ssh_user" {
  type    = string
}

variable "app_port" {
  type = number
}

variable "service_name" {
  description = "systemd service name and install directory name (/opt/<service_name>)."
  type        = string
  default     = "vertxproj-app"
}

variable "app_user" {
  description = "Unprivileged OS user that runs the server."
  type        = string
  default     = "vertxproj-user"
}

variable "jar_path" {
  type = string
}

variable "server_cert_dir" {
  type = string
}

variable "ca_dir" {
  type = string
}

variable "java_opts" {
  type    = string
}

variable "timezone" {
  type    = string
}

############################ Database (from the db module) ############################
variable "db_host" {
  description = "RDS hostname."
  type        = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "db_user" {
  description = "Database role the app connects as."
  type        = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_pool_max" {
  description = "Maximum DB connections the app opens (db.pool.size.max)."
  type        = number
  default     = 10
}