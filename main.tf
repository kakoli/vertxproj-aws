terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state for now. The database password will end up in state, so move to an
  # encrypted S3 backend before sharing this project or using it beyond dev.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Analogy : Files inside network module define the class. This block here is calling that constructor:
module "network" {
  source = "./modules/network"
# LHS - network module's internal variables. RHS - root environment's configuration variables.
# Instantiating the network module using values from your root variables
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  app_port             = var.app_port
  allowed_app_cidrs    = var.allowed_app_cidrs
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
}

module "app" {
  source               = "./modules/app"

  project_name         = var.project_name
  environment          = var.environment
  subnet_id            = module.network.public_subnet_ids[0]
  security_group_id    = module.network.app_sg_id
  instance_type        = var.instance_type
  ami_architecture     = var.ami_architecture
  root_volume_gb       = var.root_volume_gb
  ssh_public_key_path  = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path
  ssh_user             = var.ssh_user
  app_port             = var.app_port
  jar_path             = var.jar_path
  server_cert_dir      = var.server_cert_dir
  ca_dir               = var.ca_dir
  java_opts            = var.java_opts
  timezone             = var.timezone

  # From the db module: app.json is written and the service started once these are ready.
  db_host     = module.db.endpoint
  db_port     = module.db.port
  db_name     = module.db.db_name
  db_user     = module.db.app_user
  db_password = module.db.app_password
}

module "db" {
  source = "./modules/db"

  project_name         = var.project_name
  environment          = var.environment
  private_subnet_ids   = module.network.private_subnet_ids
  db_sg_id             = module.network.db_sg_id
  db_name              = var.db_name
  admin_user           = var.db_admin_user
  app_user             = var.db_app_user
  instance_class       = var.db_instance_class
  engine_version       = var.db_engine_version
  allocated_storage    = var.db_allocated_storage

  # The schema scripts run from the app server, over SSH from this machine.
  app_host             = module.app.public_ip
  ssh_user             = var.ssh_user
  ssh_private_key_path = var.ssh_private_key_path
  scripts_dir          = var.db_scripts_dir
  entry_script         = var.db_entry_script
  schema_mode          = var.db_schema_mode
}