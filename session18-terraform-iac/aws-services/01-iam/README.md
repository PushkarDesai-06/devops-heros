# 01 – AWS IAM (Identity and Access Management) · Governance

## What is IAM?

IAM is the global AWS service that answers two questions for **every** API call:

1. **Authentication**: *who* is making the request? (user, role session, root, federated identity)
2. **Authorization**: *is this principal allowed* to perform this action on this resource, under these conditions?

IAM is global (not regional), and it is free. Every request to AWS (console, CLI, SDK, Terraform) is signed with credentials and evaluated against policies.

```
Principal ──(signed request: action + resource + context)──► AWS ──► policy evaluation ──► Allow / Deny
```

## Core building blocks

| Concept | What it is | Credentials | Typical use |
| ------- | ---------- | ----------- | ----------- |
| **Root user** | The email that created the account. Has unrestricted access. | Password (+MFA), never access keys | Billing / account-level tasks only. Lock it away with MFA. |
| **User** | A long-lived identity for one person or app | Console password and/or access keys (`AKIA…`) | Humans in small accounts. Prefer SSO (IAM Identity Center) for humans. |
| **Group** | A collection of users. Policies attached to the group apply to all members. | None (not a principal) | `Developers`, `Admins`, `ReadOnly` |
| **Role** | An identity *without* long-term credentials. Anyone trusted can **assume** it and gets temporary credentials from STS. | Temporary (`ASIA…` + session token), 15 min – 12 h | EC2/Lambda/EKS workloads, cross-account access, CI/CD (OIDC), federation |
| **Policy** | A JSON document that grants or denies permissions | – | Attached to users/groups/roles or resources |

### Users vs roles

| | User | Role |
|-|------|------|
| Credentials | Long-term (rotate them yourself) | Temporary, rotated automatically |
| Who uses it | One specific person/app | Anyone allowed by the **trust policy** |
| Best for | Break-glass, legacy apps | Everything else (services, CI, cross-account) |

## Policies

### Policy types

| Type | Attached to | Purpose |
| ---- | ----------- | ------- |
| AWS managed | Identities | Ready-made by AWS (`ReadOnlyAccess`, `AmazonS3ReadOnlyAccess`) |
| Customer managed | Identities | Your own reusable, versioned policies |
| Inline | One identity | Strict 1:1 policy, deleted with the identity |
| Resource-based | Resources (S3 bucket, SQS, KMS key…) | Says *who* can access this resource. Has a `Principal` element. |
| Trust policy | A role | Says who may `sts:AssumeRole` |
| Permissions boundary | User/role | The **maximum** permissions an identity can ever get |
| SCP (Organizations) | Account / OU | Guardrails for whole accounts |
| Session policy | An assumed-role session | Further restricts one session |

### Anatomy of a policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOneBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::devopsheros-s18-tf-demo-2909",
        "arn:aws:s3:::devopsheros-s18-tf-demo-2909/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "true" }
      }
    }
  ]
}
```

| Element | Meaning |
| ------- | ------- |
| `Version` | Always `"2012-10-17"` (the policy language version, not a date you pick) |
| `Effect` | `Allow` or `Deny` |
| `Action` | `service:Operation`. Wildcards allowed (`s3:Get*`). |
| `Resource` | ARN(s) the statement applies to |
| `Condition` | Optional: IP, MFA, tags, TLS, time, org ID… |
| `Principal` | Only in resource-based/trust policies |

### A role trust policy (EC2 can assume this role)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

## Permissions: how a request is evaluated

1. By default everything is **implicitly denied**.
2. If any applicable policy has an explicit **Deny**, the result is DENY (this always wins).
3. SCPs, permission boundaries and session policies must also *allow* the action (they are filters).
4. Otherwise, if an identity-based or resource-based policy **Allows** it, the result is ALLOW.
5. Otherwise the request stays implicitly denied.

> Explicit Deny > Allow > implicit Deny.

## Least privilege

Grant only the actions, on only the resources, under only the conditions that a job needs, and no more.

How to get there in practice:
- Start from AWS managed *job-function* policies, then narrow them down.
- Use **IAM Access Analyzer** to generate a policy from CloudTrail activity and to find unused permissions.
- Scope `Resource` to specific ARNs, not `*`.
- Add conditions (`aws:SourceIp`, `aws:PrincipalOrgID`, `aws:MultiFactorAuthPresent`, tag-based ABAC).
- Review regularly with *Last accessed* information.

## IAM best practices

| Practice | Why |
| -------- | --- |
| Enable MFA on root, don't create root access keys | The root user can't be restricted by IAM policies |
| Use IAM Identity Center (SSO) for humans | Central users and short-lived credentials |
| Use **roles** for workloads (EC2 instance profile, IRSA/Pod Identity on EKS, Lambda execution role) | No keys on disk |
| Use OIDC federation for CI (GitHub Actions → `AssumeRoleWithWebIdentity`) | No long-lived CI secrets |
| Attach policies to groups, not users | Easier to manage |
| Rotate / remove unused access keys, enforce a password policy | Reduces credential leak blast radius |
| Use permission boundaries and SCPs as guardrails | Stops privilege escalation |
| Enable CloudTrail and Access Analyzer | Audit who did what, find external access |

## Common use cases

- EC2 instance reads from S3 via an **instance profile** (role), with no keys on the box.
- GitHub Actions deploys Terraform by assuming a role through OIDC.
- Cross-account access: account B's role trusts account A.
- Developers get `ReadOnlyAccess` in prod and `PowerUserAccess` in dev.
- A service-linked role lets an AWS service (for example Auto Scaling) act on your behalf.

## CLI & Terraform examples

```bash
aws iam create-group --group-name Developers
aws iam attach-group-policy --group-name Developers \
    --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam create-user --user-name alice
aws iam add-user-to-group --user-name alice --group-name Developers
aws sts get-caller-identity            # who am I?
aws sts assume-role --role-arn arn:aws:iam::123456789012:role/deploy --role-session-name demo
```

```hcl
resource "aws_iam_role" "ec2_s3_reader" {
  name = "ec2-s3-reader"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_ro" {
  role       = aws_iam_role.ec2_s3_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_s3_reader" {
  name = "ec2-s3-reader"
  role = aws_iam_role.ec2_s3_reader.name
}
```

## Interview Q&A

**Q1. What's the difference between an IAM user and a role?**
A user has long-term credentials tied to one identity. A role has no credentials of its own. A trusted principal assumes it and receives temporary STS credentials.

**Q2. If one policy allows `s3:DeleteObject` and another explicitly denies it, what happens?**
The request is denied, because an explicit Deny always wins.

**Q3. What is a trust policy?**
The resource-based policy on a role that defines *who* can assume it (a service, account, user or OIDC provider).

**Q4. How do you give an EC2 instance access to S3 securely?**
Create a role that trusts `ec2.amazonaws.com`, attach a least-privilege S3 policy, and attach it to the instance through an instance profile. The SDK picks up the credentials from the instance metadata service (IMDSv2).

**Q5. Identity-based vs resource-based policy?**
An identity-based policy is attached to a user/group/role and has no `Principal` element. A resource-based policy is attached to a resource (S3 bucket, KMS key) and names the `Principal`. Resource-based policies enable cross-account access without assuming a role.

**Q6. What is a permissions boundary?**
A managed policy that sets the *maximum* permissions an identity can have. The effective permissions are the intersection of the boundary and the identity policies.

**Q7. Is IAM regional?**
No. IAM is global. STS has regional endpoints.

**Q8. How would you find unused permissions?**
Use IAM Access Analyzer unused-access findings and the "last accessed" data in the console or with `aws iam generate-service-last-accessed-details`.
