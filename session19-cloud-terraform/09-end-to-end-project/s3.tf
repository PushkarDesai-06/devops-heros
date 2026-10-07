resource "aws_s3_bucket" "artifacts" {
  # AWS bucket names are global; bucket_prefix lets Terraform append a unique suffix.
  bucket_prefix = "${var.project_name}-artifacts-"
  force_destroy = true # lab only: lets "terraform destroy" remove a non-empty bucket

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-artifacts"
  })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Keep a copy of the EC2 bootstrap template next to the infrastructure it belongs to.
resource "aws_s3_object" "user_data" {
  bucket       = aws_s3_bucket.artifacts.id
  key          = "bootstrap/user_data.sh.tftpl"
  source       = "${path.module}/templates/user_data.sh.tftpl"
  etag         = filemd5("${path.module}/templates/user_data.sh.tftpl")
  content_type = "text/plain"
}

# A small JSON "build record". It references the VPC, subnet and EC2 instance,
# so Terraform can only create it after those exist (implicit dependencies).
resource "aws_s3_object" "build_info" {
  bucket       = aws_s3_bucket.artifacts.id
  key          = "build-info.json"
  content_type = "application/json"

  content = jsonencode({
    project     = var.project_name
    region      = var.aws_region
    vpc_id      = aws_vpc.main.id
    subnet_id   = aws_subnet.public.id
    instance_id = aws_instance.web.id
    ami_id      = aws_instance.web.ami
    public_ip   = aws_instance.web.public_ip
  })
}
