variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets (at least 2 AZs) for the DB subnet group."
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group that allows 5432 from the app server only."
  type        = string
}

variable "db_name" {
  type    = string
}

variable "admin_user" {
  description = "RDS master user. Used only to bootstrap; the app never uses it."
  type        = string
}

variable "app_user" {
  description = "Database role the application connects as. Owns the database."
  type        = string
}

variable "instance_class" {
  type    = string
}

variable "engine_version" {
  description = "PostgreSQL version. A major-only value (e.g. 16) takes the latest minor."
  type        = string
}

variable "allocated_storage" {
  description = "Storage in GB (gp3 minimum is 20)."
  type        = number
}

# ---- Used to run the schema scripts from the EC2 instance ----
variable "app_host" {
  description = "Public IP of the app server (SSH target for the schema run)."
  type        = string
}

variable "ssh_user" {
  type    = string
}

variable "ssh_private_key_path" {
  type = string
}

variable "scripts_dir" {
  description = "Local folder with setup.sql and the files it includes (uploaded with subfolders)."
  type        = string
}

variable "entry_script" {
  description = "The one script psql runs. It lives directly in scripts_dir and pulls in the others with \\i."
  type        = string
}

variable "schema_mode" {
  description = "once: run the entry script only if it was never applied. rebuild: run it whenever the schema step runs (drops tables, deletes data)."
  type        = string

  validation {
    condition     = contains(["once", "rebuild"], var.schema_mode)
    error_message = "schema_mode must be once or rebuild."
  }
}
