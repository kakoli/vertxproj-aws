output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

# Waits for the internet gateway and public routing, so that Elastic IP(fixed public IPv4 address) can be attached to the ec2 instance.
# Need for depends_on - An EIP can only be attached to an instance whose VPC has an internet gateway attached, and the subnet needs a
# route to it. Terraform doesn’t see that requirement since the EIP resource never references the gateway/route associations.
# Hence, the need for explicit depends on
output "public_subnet_ids" {
  value      = aws_subnet.public[*].id
  depends_on = [aws_internet_gateway.main, aws_route_table_association.public]
}

# Consumers wait for the firewall rules to exist before the instance boots up.
output "app_sg_id" {
  value = aws_security_group.app.id
  depends_on = [aws_vpc_security_group_ingress_rule.app_port,
                aws_vpc_security_group_ingress_rule.app_ssh,
                aws_vpc_security_group_egress_rule.app_all]
}

output "db_sg_id" {
  value = aws_security_group.db.id
}
