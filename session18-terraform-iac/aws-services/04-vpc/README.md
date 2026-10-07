# 04 – Amazon VPC (Virtual Private Cloud) · Networking

## What is a VPC?

A VPC is your own logically isolated private network inside an AWS **region**. You choose its IP range, split it into subnets (one AZ each), and control routing and firewalls. Every account has a **default VPC** per region (`172.31.0.0/16`, a public subnet in every AZ). For real workloads, create your own.

```
VPC 10.0.0.0/16  (us-east-1)
├── us-east-1a
│   ├── public-a   10.0.1.0/24   ── route 0.0.0.0/0 → IGW      (ALB, NAT GW, bastion)
│   └── private-a  10.0.11.0/24  ── route 0.0.0.0/0 → NAT GW   (app servers, EKS nodes)
├── us-east-1b
│   ├── public-b   10.0.2.0/24
│   └── private-b  10.0.12.0/24
└── Internet Gateway (attached to the VPC)
```

## CIDR

CIDR (Classless Inter-Domain Routing) notation `a.b.c.d/n` means the first *n* bits are the network part.

| CIDR | Addresses | Usable in an AWS subnet (−5) |
| ---- | --------- | ---------------------------- |
| `/16` | 65,536 | – (largest VPC size) |
| `/20` | 4,096 | 4,091 |
| `/24` | 256 | 251 |
| `/28` | 16 | 11 (smallest subnet size) |

- Use private RFC 1918 ranges: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
- Plan **non-overlapping** CIDRs if you will ever peer VPCs or connect on-prem networks.
- AWS reserves **5 IPs per subnet**: network address, `.1` VPC router, `.2` DNS, `.3` reserved for future use, and the broadcast address.
- You can add secondary CIDRs and IPv6 `/56` blocks later.

## Subnets

- A range of the VPC CIDR inside **one AZ**. Spread subnets across ≥2 AZs for high availability.
- Each subnet is associated with exactly one route table and one NACL.
- `map_public_ip_on_launch` controls auto-assigning public IPv4 addresses.

## Route tables

A set of rules `destination → target` evaluated by **longest prefix match**.

| Destination | Target | Meaning |
| ----------- | ------ | ------- |
| `10.0.0.0/16` | `local` | Always present, for traffic inside the VPC |
| `0.0.0.0/0` | `igw-…` | Internet via Internet Gateway (makes the subnet **public**) |
| `0.0.0.0/0` | `nat-…` | Outbound-only internet via NAT (private subnet) |
| `pl-…` (S3 prefix list) | `vpce-…` | Gateway endpoint to S3/DynamoDB, which stays on the AWS network |
| `172.20.0.0/16` | `pcx-…` / `tgw-…` | Peering / Transit Gateway |

The main route table is used by subnets that don't have an explicit association.

## Internet Gateway (IGW)

- A horizontally scaled, highly available, free gateway that you attach to **one** VPC.
- Allows inbound and outbound internet traffic for resources that have a public IP. It does 1:1 NAT between private and public IPs.
- Needs: IGW attached + route `0.0.0.0/0 → igw` + public IP on the instance + SG/NACL allow.

## NAT Gateway

- Lets **private** subnets reach the internet (for OS updates, pulling images or calling APIs) while blocking inbound connections that start from the internet.
- Lives in a **public** subnet with an Elastic IP (public NAT).
- It's AZ-scoped, so for HA create one per AZ and point each private route table at the NAT in its own AZ.
- Billed per hour + per GB processed. It's often the surprise item on the bill, so use VPC endpoints for S3/DynamoDB/ECR traffic.
- The older alternative was a NAT *instance*, which you had to manage yourself.

## Security Groups (instance level)

- **Stateful**, allow rules only, attached to ENIs.
- Can reference other SGs (`source_security_group_id`) to build tiers: ALB SG → App SG → DB SG.

## Network ACLs (subnet level)

- **Stateless**: you must allow return traffic explicitly (ephemeral ports `1024-65535`).
- Allow **and deny** rules, evaluated in **rule-number order**, and the first match wins. The final `*` rule denies.
- The default NACL allows everything. A custom NACL denies everything until you add rules.

### Security Group vs NACL

| | Security Group | Network ACL |
| - | -------------- | ----------- |
| Level | ENI / instance | Subnet |
| State | Stateful | Stateless |
| Rules | Allow only | Allow + Deny |
| Evaluation | All rules together | Lowest number first, first match |
| Default (custom) | Deny in, allow out | Deny all |
| Typical use | Main firewall | Coarse guardrail, block an IP range |

## Public vs private subnet

| | Public subnet | Private subnet |
| - | ------------- | -------------- |
| Default route | `0.0.0.0/0 → IGW` | `0.0.0.0/0 → NAT GW` (or none, for an isolated subnet) |
| Public IPs | Yes | No |
| Reachable from the internet | Yes (if SG allows) | No |
| Put here | Load balancers, NAT GW, bastion | App servers, databases, EKS nodes, Lambdas in VPC |

> A subnet is "public" **only because of its route table.** There is no "public" checkbox.

## Other things worth knowing

- **VPC endpoints**: *Gateway* endpoints (S3, DynamoDB) are free. *Interface* endpoints (PrivateLink) put an ENI in your subnet.
- **VPC peering**: 1:1, non-transitive. **Transit Gateway** is a hub-and-spoke model for many VPCs and on-prem networks.
- **VPC Flow Logs**: capture IP traffic metadata to CloudWatch or S3 for troubleshooting.
- **DNS**: `enableDnsSupport` / `enableDnsHostnames` (needed for private hosted zones and interface endpoints).

## Terraform example (one AZ shown)

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "devops-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "a" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.a.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}
```

## Handy CLI

```bash
aws ec2 describe-vpcs --query 'Vpcs[].[VpcId,CidrBlock,IsDefault]' --output table
aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0abc --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]' --output table
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0abc
```

## Interview Q&A

**Q1. What makes a subnet public?**
Its route table has `0.0.0.0/0` pointing to an Internet Gateway.

**Q2. Why does a private instance need a NAT Gateway, and where does the NAT live?**
To make outbound internet connections (updates, APIs) without being reachable from the internet. The NAT sits in a public subnet with an Elastic IP.

**Q3. How many usable IPs are in a /24 subnet?**
251. AWS reserves 5 of the 256.

**Q4. SG vs NACL? Which is stateful?**
The SG is stateful, allow-only and works at the instance level. The NACL is stateless, allows and denies, and works at the subnet level with ordered rules.

**Q5. My private EC2 can't reach S3. What do you check?**
The route table (NAT or S3 gateway endpoint), SG outbound rules, NACL rules including ephemeral return ports, the IAM role, the bucket policy/endpoint policy, and DNS settings.

**Q6. Is VPC peering transitive?**
No. A↔B and B↔C does not give you A↔C. Use Transit Gateway for that.

**Q7. How do you make a NAT Gateway highly available?**
Create one NAT Gateway per AZ, each in that AZ's public subnet, with each private route table pointing to its local NAT.

**Q8. How do you reduce NAT Gateway costs?**
Use gateway endpoints for S3/DynamoDB, interface endpoints for ECR/STS etc., and keep heavy traffic in the same AZ.
