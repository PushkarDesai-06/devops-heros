# 03 – Amazon S3 (Simple Storage Service) · Storage

## What is S3?

S3 is **object storage** with a simple HTTP API: you `PUT` and `GET` whole objects by key. It's designed for 99.999999999% (11 nines) durability by storing data redundantly across at least 3 AZs (except One Zone classes), and it scales without limits on the total amount you store.

| | S3 (object) | EBS (block) | EFS (file) |
| - | ----------- | ----------- | ---------- |
| Access | HTTPS API | Mounted disk on 1 instance (per AZ) | NFS mount, many instances |
| Unit | Object (≤ 5 TB) | Blocks | Files |
| Typical use | Backups, static assets, data lake, Terraform state | OS/DB disks | Shared files |

## Buckets

- A container for objects. The name is **globally unique** across all AWS accounts, 3–63 characters, lowercase, DNS-compatible.
- Created in **one region** (data stays there unless you replicate it).
- Default limit: 10,000 general purpose buckets per account (can be raised).
- Since April 2023, new buckets have **Block Public Access ON** and **ACLs disabled** (Object Ownership = BucketOwnerEnforced).
- Since January 2023, all new objects are encrypted with SSE-S3 by default.

## Objects

| Part | Description |
| ---- | ----------- |
| Key | Full "path", for example `notes/README.md`. S3 is flat, and "folders" are just key prefixes. |
| Value | The data, 0 B – 5 TB (single PUT ≤ 5 GB, use multipart above ~100 MB) |
| Version ID | When versioning is enabled |
| Metadata | System (`Content-Type`, `ETag`…) + user `x-amz-meta-*` |
| Tags | Up to 10 key/value tags (for lifecycle, IAM conditions, cost) |

Consistency: S3 has **strong read-after-write consistency** for all PUTs, DELETEs and LISTs.

URL forms: `s3://bucket/key`, `https://bucket.s3.us-east-1.amazonaws.com/key`.

## Storage classes

| Class | Min. duration | Retrieval | AZs | Use |
| ----- | ------------- | --------- | --- | --- |
| S3 Standard | – | ms | ≥3 | Frequently accessed data |
| S3 Intelligent-Tiering | – | ms (archive tiers optional) | ≥3 | Unknown/changing access patterns |
| S3 Standard-IA | 30 days | ms, per-GB retrieval fee | ≥3 | Infrequent access, quick when needed |
| S3 One Zone-IA | 30 days | ms | 1 | Re-creatable infrequent data |
| S3 Express One Zone | – | single-digit ms | 1 (directory bucket) | Latency-critical analytics/ML |
| Glacier Instant Retrieval | 90 days | ms | ≥3 | Archive accessed ~quarterly |
| Glacier Flexible Retrieval | 90 days | minutes – 12 h | ≥3 | Backups/archives |
| Glacier Deep Archive | 180 days | 12 – 48 h | ≥3 | Compliance, 7–10 year retention |

## Versioning

- States: **Unversioned** (default) → **Enabled** → **Suspended**. You can never go back to unversioned.
- Every overwrite creates a new version. A DELETE adds a **delete marker**, and older versions stay recoverable.
- Protects against accidental deletes and overwrites. Required for replication.
- **MFA Delete** (root only, via CLI) requires MFA to permanently delete versions.
- Each version is billed, so pair versioning with a lifecycle rule for noncurrent versions.

```bash
aws s3api put-bucket-versioning --bucket my-bucket --versioning-configuration Status=Enabled
aws s3api get-bucket-versioning --bucket my-bucket     # -> {"Status": "Enabled"}
aws s3api list-object-versions --bucket my-bucket --prefix notes/
```

## Lifecycle policies

Rules (filtered by prefix or tag) that automatically **transition** objects to cheaper classes or **expire** them.

```json
{
  "Rules": [{
    "ID": "logs-tiering",
    "Status": "Enabled",
    "Filter": { "Prefix": "logs/" },
    "Transitions": [
      { "Days": 30,  "StorageClass": "STANDARD_IA" },
      { "Days": 90,  "StorageClass": "GLACIER" }
    ],
    "Expiration": { "Days": 365 },
    "NoncurrentVersionExpiration": { "NoncurrentDays": 30 },
    "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
  }]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration --bucket my-bucket --lifecycle-configuration file://lifecycle.json
```

## Encryption

| Option | Keys managed by | Notes |
| ------ | --------------- | ----- |
| **SSE-S3** (`AES256`) | S3 | Default for all new objects, no cost |
| **SSE-KMS** (`aws:kms`) | AWS KMS (AWS-managed or customer key) | Audit in CloudTrail, key policies. Enable **S3 Bucket Keys** to cut KMS costs. |
| **DSSE-KMS** | KMS, two layers | Compliance requiring dual-layer encryption |
| **SSE-C** | You send the key with every request | AWS doesn't store the key |
| Client-side | You | Encrypt before upload |

In transit: enforce HTTPS with a bucket policy condition `aws:SecureTransport = false → Deny`.

## Bucket policies

A resource-based JSON policy on the bucket. Use it for cross-account access, enforcing TLS/encryption, restricting to a VPC endpoint or granting CloudFront access.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "AllowCloudFrontRead",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-bucket/*",
      "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::123456789012:distribution/E1ABCDEF2GHIJK" } }
    }
  ]
}
```

Access is granted if an IAM policy **or** the bucket policy allows it (same account) and nothing explicitly denies it. **Block Public Access** overrides any policy that would make the bucket public.

## Common use cases

- Static website hosting (usually behind CloudFront).
- Backups and disaster recovery, log archives (ALB, CloudTrail, VPC Flow Logs).
- Data lake for Athena, EMR and Glue.
- Terraform remote state (`backend "s3"` with `use_lockfile = true`).
- Artifact storage for CI/CD, ML datasets and media.

## Terraform example (v6 provider style: one resource per feature)

```hcl
resource "aws_s3_bucket" "this" {
  bucket = "devopsheros-s18-tf-demo-2909"
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
```

## Handy CLI

```bash
aws s3 ls                                   # list buckets
aws s3 cp file.txt s3://my-bucket/dir/      # upload
aws s3 sync ./site s3://my-bucket --delete  # mirror a folder
aws s3 presign s3://my-bucket/dir/file.txt --expires-in 3600   # temporary download URL
aws s3 rb s3://my-bucket --force            # empty + delete bucket
```

## Interview Q&A

**Q1. Why must bucket names be globally unique?**
Bucket names form part of DNS hostnames (`bucket.s3.amazonaws.com`), and the namespace is shared across all accounts.

**Q2. How do you recover a deleted object?**
If versioning is enabled, delete the **delete marker** (or copy a previous version back). Without versioning it is gone.

**Q3. SSE-S3 vs SSE-KMS?**
Both encrypt at rest with AES-256. SSE-KMS uses KMS keys, which gives you key policies, rotation control and CloudTrail auditing of each key use, at extra cost (reduced by Bucket Keys).

**Q4. How do you make a private bucket's file temporarily downloadable?**
Generate a **pre-signed URL** (`aws s3 presign`), which inherits the signer's permissions for a limited time.

**Q5. How do you serve a static site securely from S3?**
Keep the bucket private, put CloudFront in front with Origin Access Control, and allow only that distribution in the bucket policy.

**Q6. What is the difference between a lifecycle transition and expiration?**
A transition moves an object to a cheaper storage class. Expiration deletes it (or its noncurrent versions).

**Q7. What does `force_destroy = true` do in Terraform?**
On `terraform destroy`, the provider deletes all objects (and versions) first, so deleting a non-empty bucket succeeds instead of failing with `BucketNotEmpty`.

**Q8. Is S3 eventually consistent?**
Not any more. Since December 2020, S3 provides strong read-after-write consistency for all operations.
