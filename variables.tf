############################ General ############################
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project name, used in resource names and tags."
  type        = string
  default     = "vertxproj"
}

variable "environment" {
  description = "Environment name (dev, test, prod)."
  type        = string
  default     = "dev"
}

############################ Network ############################
variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (the app server uses the first)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for RDS. At least 2, in different AZs."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

# Machine that sends API calls, ie Postman/curl. This is open to all via default value.
variable "allowed_app_cidrs" {
  description = "CIDRs allowed to reach the app port, Default is open to the internet: mTLS (client-auth REQUIRED)"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_app_cidrs) > 0 && alltrue([for c in var.allowed_app_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_app_cidrs must be a non-empty list of valid CIDR blocks."
  }
}
# No default values for the below variables, hence given in terraform.tfvars.
# Machine running terraform apply, because the provisioners SSH from there.
# can(cidrhost(c, 0) returns the first address of the CIDR, or throws an error if the string isn’t a valid CIDR.
variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH to the app server. Must include the machine running terraform apply."
  type        = list(string)

  validation {
    condition     = length(var.allowed_ssh_cidrs) > 0 && alltrue([for c in var.allowed_ssh_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_ssh_cidrs must be a non-empty list of valid CIDR blocks."
  }
  validation {
    condition     = !contains(var.allowed_ssh_cidrs, "0.0.0.0/0")
    error_message = "Do not open SSH to 0.0.0.0/0. Use your own IP, e.g. x.x.x.x/32."
  }
}

############################ App server ############################
variable "app_port" {
  description = "Port the Vert.x server listens on (HTTPS with mTLS)."
  type        = number
  default     = 9443
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ami_architecture" {
  description = "AMI architecture: x86_64 (t3, m5 ...) or arm64 (t4g, m6g ...). Must match instance_type."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.ami_architecture)
    error_message = "ami_architecture must be x86_64 or arm64."
  }
}

variable "root_volume_gb" {
  description = "Root volume size in GB."
  type        = number
  default     = 20
}

variable "ssh_public_key_path" {
  description = "Public key uploaded to AWS as the instance key pair."
  type        = string
  default     = "~/.ssh/vertxproj-aws.pub"
}

variable "ssh_private_key_path" {
  description = "Matching private key, used by Terraform's SSH provisioners."
  type        = string
  default     = "~/.ssh/vertxproj-aws"
}

variable "ssh_user" {
  description = "Login user of the AMI (ec2-user for Amazon Linux)."
  type        = string
  default     = "ec2-user"
}

############################ Deployment artifacts ############################
# Relative paths are resolved from the directory where you run terraform.
variable "jar_path" {
  description = "Path to the fat jar built by mvn package."
  type        = string
}

variable "server_cert_dir" {
  description = "Folder with the AWS server certificate and key (folks-app.crt / folks-app.key)."
  type        = string
}

variable "ca_dir" {
  description = "Folder with ca_javalabs.crt only. Never include the CA private key."
  type        = string
}

variable "java_opts" {
  description = "JVM options, e.g. heap size. No debug or javax.net.debug flags on a server."
  type        = string
  default     = "-Xmx384m"
}

variable "timezone" {
  description = "JVM time zone (-Duser.timezone). EC2 defaults to UTC."
  type        = string
  default     = "Asia/Kolkata"
}

############################ Database ############################
variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "vertxprojdb"
}

variable "db_admin_user" {
  description = "RDS master user. Used only to bootstrap; \"admin\" is reserved by RDS."
  type        = string
  default     = "dbadmin"
}

variable "db_app_user" {
  description = "Database role the application connects as."
  type        = string
  default     = "test"
}

variable "db_instance_class" {
  description = "RDS instance class. Check Free Tier eligibility for your account."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL version. A major-only value takes the latest minor."
  type        = string
  default     = "16"
}

variable "db_allocated_storage" {
  description = "Database storage in GB."
  type        = number
  default     = 20
}

variable "db_scripts_dir" {
  description = "Local folder with setup.sql and the files it includes (schema/, data/)."
  type        = string
  default     = "./dbScripts"
}

variable "db_entry_script" {
  description = "The one script run against the database. It must be directly in db_scripts_dir and include the others with \\i."
  type        = string
  default     = "setup.sql"
}

variable "db_schema_mode" {
  description = "once = run the entry script only if never applied; a later change only prints a warning. rebuild = run it whenever the schema step runs. setup.sql drops the tables first, so rebuild DELETES DATA."
  type        = string
  default     = "once"

  validation {
    condition     = contains(["once", "rebuild"], var.db_schema_mode)
    error_message = "db_schema_mode must be once or rebuild."
  }
}
