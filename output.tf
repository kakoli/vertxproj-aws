output "app_public_ip" {
  description = "Elastic IP of the app server. Put this in the server certificate's SAN."
  value       = module.app.public_ip
}

output "app_base_url" {
  description = "Base URL for Postman (needs the client certificate and your CA trusted)."
  value       = "https://${module.app.public_ip}:${var.app_port}/api/v1"
}

output "ssh_command" {
  description = "SSH into the app server."
  value       = module.app.ssh_command
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets, used by the db module in the next step."
  value       = module.network.private_subnet_ids
}

output "db_endpoint" {
  description = "RDS hostname (private, reachable from the app server only)."
  value       = module.db.endpoint
}

output "db_name" {
  value = module.db.db_name
}

output "db_app_user" {
  value = module.db.app_user
}

output "db_app_password" {
  description = "terraform output -raw db_app_password"
  value       = module.db.app_password
  sensitive   = true
}

output "db_admin_password" {
  description = "terraform output -raw db_admin_password"
  value       = module.db.admin_password
  sensitive   = true
}