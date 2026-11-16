data "aws_availability_zones" "available" {
  state = "available"
}
# Values defined inside the locals block is strictly private to the module where it lives. Hence, each module has its own name.
# local block is to build the naming prefix once and reuse it in every resource
locals {
  name = "${var.project_name}-${var.environment}"
  # slice(list, start_index, end_index)
  azs  = slice(data.aws_availability_zones.available.names, 0, max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs)))
}

############################ VPC ############################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

############################ Subnets ############################
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index] # Loop mechanism
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.name}-private-${count.index + 1}" }
}

############################ Routing ############################
# While Route Tables manage routing (where traffic goes), Security Groups manage firewall access (who is allowed inside).
# Route table is at Subnet Level, governs the entire neighborhood block.
# Security Group is at Instance Level: Attaches directly to your t3.micro network card.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# No route to the internet: the database subnets are local-only.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################ Security group: app server ############################
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "App server: app port open, but SSH from allowed CIDRs only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_port" {
  for_each = toset(var.allowed_app_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Vert.x server"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "SSH for Terraform provisioners"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Package installs and database access"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

############################ Security group: database ############################
resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "Database: PostgreSQL from the app server only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from app server"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}
