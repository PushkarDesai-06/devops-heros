locals {
  common_tags = {
    Session   = "19"
    ManagedBy = "Terraform"
  }

  # Rendered at plan time; ${...} placeholders in the template are filled in here.
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    project_name = var.project_name
    aws_region   = var.aws_region
  })
}
