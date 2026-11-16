terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  name    = "${var.project_name}-${var.environment}"
  app_dir = "/opt/${var.service_name}"

  # First-boot setup: Install java runtime, psql client (for the schema step later) and create app user.
  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf install -y java-21-amazon-corretto-headless postgresql15
    id ${var.app_user} >/dev/null 2>&1 || useradd --system --create-home --home-dir ${local.app_dir} --shell /sbin/nologin ${var.app_user}
  EOT

  # Text of systemd service file. It tells Linux how to run Vert.x app as a managed background service.
  # ExecStartPre - If app.json is missing, systemd refuses to start the app. Hence, the app can never silently fall back to the localhost file bundled inside the jar.
  systemd_unit = <<-EOT
    [Unit]
    Description=${var.project_name} Vert.x application
    After=network-online.target
    Wants=network-online.target

    [Service]
    User=${var.app_user}
    WorkingDirectory=${local.app_dir}
    Environment="JAVA_OPTS=${var.java_opts}"

    ExecStartPre=/usr/bin/test -f ${local.app_dir}/app.json
    ExecStart=/usr/bin/java $JAVA_OPTS -Dhttp.port=${var.app_port} -Dhttp.ssl=true -Duser.timezone=${var.timezone} -jar ${local.app_dir}/app.jar
    Restart=on-failure
    RestartSec=10
    SuccessExitStatus=143
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target
  EOT

  # External app.json: found in the working directory before the copy inside the jar.
  app_json = jsonencode({   # converts values like maps, lists, and objects into JSON
    "db.config" = {
      url                = "jdbc:postgresql://${var.db_host}:${var.db_port}/${var.db_name}?sslmode=require"
      user               = var.db_user
      password           = var.db_password
      "db.pool.size.max" = var.db_pool_max
    }
  })

  certs_hash = sha256(join(",", [for f in sort(fileset(var.server_cert_dir, "**")) : filesha256("${var.server_cert_dir}/${f}")]))
  ca_hash    = sha256(join(",", [for f in sort(fileset(var.ca_dir, "**")) : filesha256("${var.ca_dir}/${f}")]))
}

############################ Instance ############################
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-${var.ami_architecture}"]
  }

  filter {
    name   = "architecture"
    values = [var.ami_architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Terraform imports your public key only (~/.ssh/vertxproj-aws.pub) into EC2 key of AWS(name 'vertxproj-dev-key')
resource "aws_key_pair" "app" {
  key_name   = "${local.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = aws_key_pair.app.key_name
  associate_public_ip_address = true
  user_data                   = local.user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # Dev only: throttle when CPU credits run out instead of paying for surplus credits.
  # Valid for t2/t3/t3a/t4g only; remove this block if you switch to another family.
  credit_specification {
    cpu_credits = "standard"
  }

  tags = { Name = "${local.name}-app" }

  lifecycle {
    # A newer Amazon Linux AMI must not replace the server on the next apply.
    ignore_changes = [ami]
  }
}

# Stable address: it survives stop/start and goes into the server certificate's SAN.
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

  tags = { Name = "${local.name}-app-eip" }
}

############################ Deploy: jar, certificates, systemd unit ############################
# Re-runs when the jar, certificates, unit file or instance change.
# app.json, the schema run and service start are added with the db module.
# Special Terraform construct that implements the standard Terraform resource lifecycle but does not provision any infrastructure.
resource "null_resource" "deploy" {
  triggers = {
    instance_id = aws_instance.app.id
    jar_hash    = filesha256(var.jar_path)
    certs_hash  = local.certs_hash
    ca_hash     = local.ca_hash
    unit_hash   = sha256(local.systemd_unit)
  }

  connection {
    type        = "ssh"
    host        = aws_eip.app.public_ip
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  # EC2 runs user_data script through a tool called cloud-init, right after the instance boots up.
  # Hence, wait is for user_data (Java, psql, app user) to finish.
  provisioner "remote-exec" {
    inline = [
      "set -e",   # forces script to exit immediately if any subsequent command fails
      "cloud-init status --wait",
      "rm -rf /tmp/stage",
      "mkdir -p /tmp/stage/server_cert /tmp/stage/ca",
    ]
  }

  provisioner "file" {
    source      = var.jar_path
    destination = "/tmp/stage/app.jar"
  }

  # Trailing slash: upload the folder's contents into the staging folder.
  provisioner "file" {
    source      = "${var.server_cert_dir}/"
    destination = "/tmp/stage/server_cert"
  }

  provisioner "file" {
    source      = "${var.ca_dir}/"
    destination = "/tmp/stage/ca"
  }

  provisioner "file" {
    content     = local.systemd_unit
    destination = "/tmp/stage/${var.service_name}.service"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo install -d -o ${var.app_user} -g ${var.app_user} -m 750 ${local.app_dir}",
      "sudo install -m 644 -o root -g root /tmp/stage/app.jar ${local.app_dir}/app.jar",
      "sudo rm -rf ${local.app_dir}/server_cert ${local.app_dir}/ca",
      "sudo cp -r /tmp/stage/server_cert ${local.app_dir}/server_cert",
      "sudo cp -r /tmp/stage/ca ${local.app_dir}/ca",
      # Certificates and keys: owned by root, readable by the app group, not writable by the app.
      "sudo chown -R root:${var.app_user} ${local.app_dir}/server_cert ${local.app_dir}/ca",
      "sudo find ${local.app_dir}/server_cert ${local.app_dir}/ca -type d -exec chmod 750 {} +",
      "sudo find ${local.app_dir}/server_cert ${local.app_dir}/ca -type f -exec chmod 640 {} +",
      "sudo install -m 644 -o root -g root /tmp/stage/${var.service_name}.service /etc/systemd/system/${var.service_name}.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl try-restart ${var.service_name}",
      "rm -rf /tmp/stage",
    ]
  }
}

############################ Configure and start ############################
# Waits for the deployed files (above) and for the database + schema (db module outputs).
# Writes app.json with the RDS settings, then enables and restarts the service.
resource "null_resource" "configure" {
  depends_on = [null_resource.deploy]

  triggers = {
    instance_id   = aws_instance.app.id
    app_json_hash = nonsensitive(sha256(local.app_json))
    deploy_id     = null_resource.deploy.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.app.public_ip
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "rm -rf /tmp/appcfg",
      "mkdir -p -m 700 /tmp/appcfg",
    ]
  }

  provisioner "file" {
    content     = local.app_json
    destination = "/tmp/appcfg/app.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo install -m 600 -o ${var.app_user} -g ${var.app_user} /tmp/appcfg/app.json ${local.app_dir}/app.json",
      "rm -rf /tmp/appcfg",
      "sudo systemctl enable ${var.service_name}",
      "sudo systemctl restart ${var.service_name}",
      # Fail the apply, with the log tail, if the server is not listening within a minute.
      "for i in $(seq 1 30); do if sudo ss -ltn | grep -q ':${var.app_port} '; then echo 'App is listening on port ${var.app_port}'; exit 0; fi; sleep 2; done; sudo journalctl -u ${var.service_name} -n 60 --no-pager; exit 1",
    ]
  }
}