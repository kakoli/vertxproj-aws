output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  description = "Elastic IP of the app server."
  value       = aws_eip.app.public_ip
}

output "private_ip" {
  value = aws_instance.app.private_ip
}

output "app_dir" {
  value = local.app_dir
}

output "service_name" {
  value = var.service_name
}

output "ssh_command" {
  value = "ssh -i ${trimsuffix(var.ssh_private_key_path, ".pub")} ${var.ssh_user}@${aws_eip.app.public_ip}"
}
