# 02 – Amazon EC2 (Elastic Compute Cloud) · Compute

## What is EC2?

EC2 provides resizable **virtual machines (instances)** in AWS data centres. You choose the OS image, CPU/RAM, storage and network, and pay per second (Linux) while the instance runs. EC2 is **IaaS**: AWS manages the hardware and hypervisor (Nitro), and you manage the OS, patches and apps.

```
Region (us-east-1)
└── Availability Zone (us-east-1a)
    └── VPC subnet
        └── EC2 instance  ◄── AMI (boot image) + instance type + EBS volumes + security groups + key pair
```

## AMI (Amazon Machine Image)

A template used to launch an instance: a root volume snapshot, launch permissions and block device mappings.

| Source | Example |
| ------ | ------- |
| AWS provided | Amazon Linux 2023, Ubuntu 24.04, Windows Server 2025 |
| Marketplace | Vendor images (firewalls, licensed software) |
| Community | Public images shared by others (verify before use) |
| Your own | "Golden images" baked with Packer or `aws ec2 create-image` |

- AMIs are **regional**. Copy one to use it in another region.
- AMI IDs differ per region, so look up the latest one with an SSM parameter:
  `aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`

## Instance types

The name format is `family` + `generation` + `attributes` + `.size`. For example `m7g.large` means general purpose, 7th generation, Graviton (ARM), large.

| Family | Optimised for | Examples | Use case |
| ------ | ------------- | -------- | -------- |
| T (burstable) | Baseline CPU + credits | `t3.micro`, `t4g.small` | Dev/test, small web apps |
| M (general) | Balanced CPU/RAM | `m7i.large` | App servers |
| C (compute) | High CPU | `c7g.xlarge` | Batch, CI runners, encoding |
| R / X (memory) | High RAM | `r7i.2xlarge` | Caches, in-memory DBs |
| I / D (storage) | Local NVMe / HDD | `i4i.large` | NoSQL, data warehousing |
| P / G / Inf / Trn (accelerated) | GPU / ML chips | `g6.xlarge`, `p5.48xlarge` | ML, graphics |

Suffixes: `g` = Graviton (ARM), `a` = AMD, `i` = Intel, `n` = enhanced networking, `d` = local NVMe.

**Pricing models**

| Model | Discount | Note |
| ----- | -------- | ---- |
| On-Demand | – | No commitment |
| Savings Plans / Reserved | up to ~72% | 1 or 3 year commitment |
| Spot | up to ~90% | Can be reclaimed with a 2-minute notice |
| Dedicated Hosts | – | Licensing / compliance |

## Key pairs

- An RSA or ED25519 key pair used for SSH (Linux) or to decrypt the Windows admin password.
- AWS stores the **public** key and injects it into `~/.ssh/authorized_keys` at first boot. You download the **private** key once.
- Lose the private key and you can't SSH in. Recover through SSM Session Manager or by attaching the volume to another instance.
- Modern alternative: **SSM Session Manager** or **EC2 Instance Connect**, which need no open port 22 and no long-lived keys.

```bash
aws ec2 create-key-pair --key-name devops-key --key-type ed25519 \
    --query KeyMaterial --output text > devops-key.pem && chmod 400 devops-key.pem
ssh -i devops-key.pem ec2-user@<public-ip>
```

## Security Groups

A **stateful** virtual firewall attached to an instance's network interface (ENI).

| Property | Value |
| -------- | ----- |
| Rules | **Allow only** (no deny rules) |
| Default | All inbound denied, all outbound allowed |
| Stateful | Return traffic is automatically allowed |
| Source | CIDR, prefix list or **another security group** (great for tiers) |
| Scope | Instance/ENI level, multiple SGs per ENI |

Example: a web tier SG allows 80/443 from `0.0.0.0/0`. The DB SG allows 5432 **from the web SG** only.

## EBS (Elastic Block Store)

Network-attached block volumes that persist independently of the instance (within one AZ).

| Type | Kind | Max IOPS | Use |
| ---- | ---- | -------- | --- |
| `gp3` | SSD, general purpose | 16,000 (3,000 baseline) | Default for most workloads |
| `io2 Block Express` | SSD, provisioned IOPS | 256,000 | Critical databases |
| `st1` | HDD, throughput | 500 | Big data, logs |
| `sc1` | HDD, cold | 250 | Infrequent access |

- **Snapshots** are incremental and stored in S3. Use them for backup, AMIs and cross-AZ/region copies.
- **Instance store** is ephemeral local disk that is lost on stop/terminate.
- `DeleteOnTermination` defaults to true for the root volume.
- Enable EBS encryption by default (KMS).

## Public vs private IP

| | Private IP | Public IPv4 | Elastic IP |
| - | ---------- | ----------- | ---------- |
| From | Subnet CIDR | AWS pool (if the subnet or launch setting enables it) | Allocated to your account |
| Reachable from internet | No | Yes (with an IGW route + SG rule) | Yes |
| Survives stop/start | Yes | **No, it changes** | Yes, it's static |
| Cost | Free | Charged per hour (since Feb 2024) | Charged per hour |

The instance itself only knows its private IP. The IGW does 1:1 NAT to the public IP.

## Instance lifecycle

```
          launch
            │
            ▼
        pending ──► running ◄──────────┐
                     │   │  │           │ start
              reboot │   │  └► stopping ─► stopped
                     ▼   │           (hibernate: RAM saved to EBS)
                  running│
                         └► shutting-down ─► terminated (gone, ~1 h visible)
```

| State | Billed for compute? | EBS kept? |
| ----- | ------------------- | --------- |
| pending / running | Yes (running) | Yes |
| stopping / stopped | No | Yes (still billed for storage) |
| terminated | No | Root deleted (default), extra volumes depend on the flag |

Stop/start moves the instance to new hardware. A reboot keeps the same host and public IP.

## Common use cases

- Web/app servers behind an ALB in an Auto Scaling Group.
- Self-managed databases, Jenkins or GitLab runners, bastion hosts.
- Kubernetes worker nodes (EKS managed node groups).
- Batch and HPC jobs on Spot capacity.
- Lift-and-shift of on-prem VMs.

## CLI & Terraform examples

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress]' --output table
aws ec2 stop-instances --instance-ids i-0abc123def4567890
```

```hcl
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "devops-key"
  user_data              = "#!/bin/bash\ndnf install -y nginx && systemctl enable --now nginx"

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  tags = { Name = "web-1" }
}
```

## Interview Q&A

**Q1. Stop vs terminate?**
Stop keeps the EBS volumes and you can start the instance again (no compute charge). Terminate deletes the instance and, by default, its root volume.

**Q2. Why did my public IP change?**
Auto-assigned public IPv4 addresses are released on stop. Use an Elastic IP or a load balancer/DNS for a stable endpoint.

**Q3. Security group vs NACL?**
An SG is stateful, allow-only and works at the instance level. A NACL is stateless, has allow and deny rules, and works at the subnet level with numbered rule evaluation.

**Q4. How do you SSH into a private instance?**
Use SSM Session Manager (no inbound port needed), a bastion host in a public subnet, or EC2 Instance Connect Endpoint.

**Q5. EBS vs instance store?**
EBS is persistent network storage in one AZ that survives stop/start and supports snapshots. Instance store is physically attached, very fast and ephemeral.

**Q6. What is user data?**
A script (or cloud-init config) that runs on first boot, used to bootstrap software.

**Q7. How does an instance get AWS credentials safely?**
Through an IAM role attached as an instance profile. Credentials come from IMDS (enforce IMDSv2).

**Q8. When would you use Spot instances?**
For fault-tolerant, stateless or flexible workloads such as CI, batch and big data, never for single-instance stateful services.
