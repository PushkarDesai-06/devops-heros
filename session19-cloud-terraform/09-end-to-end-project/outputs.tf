# Same four outputs as ../08-mini-project ...
output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "security_group_id" {
  value = aws_security_group.web.id
}

# ... plus the EC2 and S3 additions.
output "ami_id" {
  description = "Amazon Linux 2023 AMI chosen by the data source."
  value       = data.aws_ami.al2023.id
}

output "instance_id" {
  value = aws_instance.web.id
}

output "instance_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_url" {
  description = "Open this in a browser (nginx answers on port 80)."
  value       = "http://${aws_instance.web.public_ip}"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}
