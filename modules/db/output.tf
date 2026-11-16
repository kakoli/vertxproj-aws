# Values the app depends on wait for the schema step, so the app starts on a ready database.
output "endpoint" {
  description = "RDS hostname."
  value       = aws_db_instance.postgres.address
  depends_on  = [null_resource.schema]
}

output "port" {
  value = aws_db_instance.postgres.port
}

output "db_name" {
  value = var.db_name
}

output "app_user" {
  value = var.app_user
}

output "app_password" {
  value     = random_password.app.result
  sensitive = true
}

output "admin_user" {
  value = var.admin_user
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}