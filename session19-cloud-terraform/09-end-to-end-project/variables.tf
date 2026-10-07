variable "aws_region" {
  description = "AWS region for the Session 19 end-to-end project."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for the names/tags of the EC2 and S3 resources."
  type        = string
  default     = "session19-mini"
}

variable "instance_type" {
  description = "EC2 instance type for the web server."
  type        = string
  default     = "t3.micro"
}
