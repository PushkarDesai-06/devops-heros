# Latest Amazon Linux 2023 AMI (x86_64) published by Amazon in the chosen region.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "web" {
  # Implicit dependencies: referencing data.aws_ami.al2023, aws_subnet.public and
  # aws_security_group.web tells Terraform to create/read those first.
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  # Explicit dependency: nothing in this block references the route table association,
  # but user_data runs "dnf install nginx" at boot, which needs the 0.0.0.0/0 -> IGW route
  # to already be attached to the subnet. depends_on makes Terraform wait for it.
  depends_on = [aws_route_table_association.public]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web"
  })
}
