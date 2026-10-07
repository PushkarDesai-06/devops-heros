# 09 - End-to-End Project (Session 19 homework)

Terraform project that builds a small but complete AWS stack in `us-east-1`:

```text
Terraform ──► VPC 10.20.0.0/16
                ├── Internet Gateway
                ├── Public route table (0.0.0.0/0 → IGW) + association
                ├── Public subnet 10.20.1.0/24 (us-east-1a)
                │      └── Security group (80/443 in, all out)
                │             └── EC2 t3.micro, Amazon Linux 2023, nginx via user_data
                └── (outside the VPC) S3 bucket: versioning + public access block + 2 objects
```

The network layer (`main.tf`) is a copy of [`../08-mini-project/main.tf`](../08-mini-project/main.tf):
same resource addresses and attributes. This folder adds the "Optional Extension - EC2"
from the 08 README, plus an S3 bucket.

![Architecture](../screenshots/architecture.png)

---

## Files

| File | What it contains |
| --- | --- |
| `versions.tf` | `required_version`, `hashicorp/aws ~> 6.0`, `provider "aws"` (region from a variable) |
| `variables.tf` | `aws_region` (default `us-east-1`), `project_name`, `instance_type` |
| `terraform.tfvars.example` | Example values; copy to `terraform.tfvars` (git-ignored) |
| `locals.tf` | `common_tags`, rendered `user_data` (`templatefile`) |
| `main.tf` | VPC, public subnet, IGW, route table, association, security group |
| `ec2.tf` | `data.aws_ami.al2023` + `aws_instance.web` (with `depends_on`) |
| `s3.tf` | Bucket, public access block, versioning, two `aws_s3_object`s |
| `outputs.tf` | 08's four outputs + `ami_id`, `instance_id`, `instance_public_ip`, `web_url`, `s3_bucket_name` |
| `templates/user_data.sh.tftpl` | Boot script: installs nginx and writes an index page |

## Resources (12) and data sources (1)

| Address | Type | Depends on |
| --- | --- | --- |
| `aws_vpc.main` | VPC | none |
| `aws_subnet.public` | Subnet | VPC |
| `aws_internet_gateway.main` | IGW | VPC |
| `aws_route_table.public` | Route table | VPC, IGW |
| `aws_route_table_association.public` | Association | route table, subnet |
| `aws_security_group.web` | Security group | VPC |
| `data.aws_ami.al2023` | AMI lookup | none |
| `aws_instance.web` | EC2 | AMI, subnet, SG, **`depends_on` association** |
| `aws_s3_bucket.artifacts` | S3 bucket | none |
| `aws_s3_bucket_public_access_block.artifacts` | S3 setting | bucket |
| `aws_s3_bucket_versioning.artifacts` | S3 setting | bucket |
| `aws_s3_object.user_data` | S3 object | bucket |
| `aws_s3_object.build_info` | S3 object | bucket, VPC, subnet, instance |

## Run it

Prerequisites: Terraform >= 1.6, AWS CLI v2 with credentials (`aws sts get-caller-identity` works).

```bash
cd session19-cloud-terraform/09-end-to-end-project
cp terraform.tfvars.example terraform.tfvars

terraform init                 # download hashicorp/aws 6.x
terraform fmt -recursive       # format
terraform validate             # "Success! The configuration is valid."
terraform plan -out=tfplan     # Plan: 12 to add, 0 to change, 0 to destroy.
terraform apply tfplan         # Apply complete! Resources: 12 added ...

terraform output               # IDs, public IP, web_url, bucket name
terraform state list           # 12 resources + data.aws_ami.al2023
curl -i "$(terraform output -raw web_url)"   # nginx answers (give user_data ~1 minute)
terraform graph | dot -Tsvg > graph.svg      # dependency graph (needs graphviz)
```

## Clean up (important: EC2 costs money)

```bash
terraform plan -destroy
terraform destroy              # type: yes
# Destroy complete! Resources: 12 destroyed.
```

## Notes

- There is no SSH rule and no key pair on purpose. Use EC2 Instance Connect or SSM if you need a shell.
- `force_destroy = true` on the bucket is only for the lab, so `destroy` can remove a non-empty bucket.
- `data.aws_ami.al2023` uses `most_recent = true`. If Amazon publishes a newer AMI, the next plan
  will want to **replace** the instance. Pin `ami` or add `lifecycle { ignore_changes = [ami] }` if you want to avoid that.
