# 05 – Amazon DynamoDB & Amazon RDS · Databases

| | DynamoDB | RDS |
| - | -------- | --- |
| Model | NoSQL key-value / document | Relational (SQL) |
| Schema | Schemaless (only keys are fixed) | Fixed tables, columns, constraints |
| Scaling | Horizontal, automatic, virtually unlimited | Vertical (instance size) + read replicas |
| Management | Fully serverless, no instances | Managed DB **instances** (you pick the size) |
| Latency | Single-digit ms at any scale | Depends on query and instance |
| Queries | By key (GetItem/Query), limited Scan | Full SQL, joins, aggregations |
| Transactions | Yes (up to 100 items) | Full ACID |
| Pick when | Known access patterns, massive scale | Complex queries, relations, existing SQL apps |

---

## Part A – Amazon DynamoDB

### NoSQL

DynamoDB is a fully managed, serverless **key-value and document** database. Data is automatically partitioned across storage nodes and replicated across 3 AZs. You design the table around your **access patterns**, not around normalised entities.

### Tables, items, attributes

| Term | SQL analogy | Notes |
| ---- | ----------- | ----- |
| **Table** | Table | A collection of items, the only thing you create |
| **Item** | Row | Max **400 KB**. Each item can have different attributes. |
| **Attribute** | Column | Types: `S`, `N`, `B`, `BOOL`, `NULL`, `M` (map), `L` (list), `SS`/`NS`/`BS` (sets) |

```json
{
  "UserId":   { "S": "u#1001" },
  "OrderId":  { "S": "2026-09-29#A17" },
  "Total":    { "N": "499.00" },
  "Status":   { "S": "SHIPPED" },
  "Items":    { "L": [ { "M": { "sku": { "S": "BOOK-42" }, "qty": { "N": "1" } } } ] }
}
```

### Primary key: partition key and sort key

| Key type | Made of | Uniqueness |
| -------- | ------- | ---------- |
| Simple | **Partition key** (hash key) only | PK value must be unique |
| Composite | **Partition key + sort key** (range key) | The (PK, SK) pair must be unique |

- The **partition key** is hashed to choose the physical partition. Pick a high-cardinality key (userId, deviceId) to avoid hot partitions.
- The **sort key** orders items within a partition and enables range queries: `begins_with`, `between`, `>`, `<`.
- Example: `PK = UserId`, `SK = OrderDate#OrderId` lets you get all orders for a user in September 2026 with a single `Query`.

**Secondary indexes**
- **GSI** (Global Secondary Index): a different PK/SK, can be added any time, eventually consistent.
- **LSI** (Local Secondary Index): same PK, different SK, must be defined at table creation.

**Capacity modes**
- **On-demand**: pay per request, no planning. This is the default choice.
- **Provisioned**: set RCU/WCU (with auto scaling), cheaper for steady traffic.

**Other features:** TTL (auto-expire items), Streams (change data capture → Lambda), Global Tables (multi-region active-active), PITR (point-in-time recovery, 35 days), DAX (in-memory cache), encryption at rest by default.

### DynamoDB use cases

- User sessions, shopping carts, user profiles.
- Gaming leaderboards, IoT telemetry, ad-tech counters.
- Serverless backends (API Gateway + Lambda + DynamoDB).
- Metadata stores, idempotency keys, and Terraform state locking in older setups (`dynamodb_table`).

### Example

```bash
aws dynamodb create-table --table-name Orders \
  --attribute-definitions AttributeName=UserId,AttributeType=S AttributeName=OrderId,AttributeType=S \
  --key-schema AttributeName=UserId,KeyType=HASH AttributeName=OrderId,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

aws dynamodb query --table-name Orders \
  --key-condition-expression "UserId = :u AND begins_with(OrderId, :m)" \
  --expression-attribute-values '{":u":{"S":"u#1001"},":m":{"S":"2026-09"}}'
```

```hcl
resource "aws_dynamodb_table" "orders" {
  name         = "Orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "OrderId"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "OrderId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }
}
```

---

## Part B – Amazon RDS (Relational Database Service)

### Relational database

RDS runs a managed relational database engine for you. AWS handles provisioning, OS and engine patching, backups, monitoring and failover. You handle the schema, queries, indexes and parameter tuning. You still choose an instance size and storage (it's not serverless, except Aurora Serverless v2).

### Supported engines

| Engine | Notes |
| ------ | ----- |
| **Amazon Aurora** (MySQL- and PostgreSQL-compatible) | AWS-built, storage auto-grows to 128 TiB, 6 copies across 3 AZs, up to 15 replicas, Serverless v2 option |
| PostgreSQL | Most popular open-source choice |
| MySQL | |
| MariaDB | |
| Oracle | BYOL or license-included |
| Microsoft SQL Server | License-included |
| Db2 | IBM Db2 (BYOL / marketplace) |

### DB instances

- A DB instance = an isolated database environment with a class (for example `db.t4g.micro`, `db.m7g.large`, `db.r7g.xlarge`) and EBS-backed storage (`gp3`, `io2`).
- It lives in a **DB subnet group** (private subnets in ≥2 AZs) inside your VPC.
- Configured with **parameter groups** (engine settings) and **option groups**.
- Storage autoscaling can grow the disk automatically.
- There is no SSH access. You connect over the engine port using the endpoint DNS name.

### Security

| Layer | How |
| ----- | --- |
| Network | Private subnets, `publicly_accessible = false`, security group allowing 5432/3306 **only from the app SG** |
| Authentication | Master user (store it in **Secrets Manager** with `manage_master_user_password`), DB users, **IAM database authentication** |
| Encryption at rest | KMS (must be chosen at creation). It also covers snapshots, backups and replicas. |
| Encryption in transit | TLS. Enforce with `rds.force_ssl=1` (Postgres) / `require_secure_transport` (MySQL). |
| Audit | CloudTrail (API), engine logs to CloudWatch, Database Activity Streams |

### Backups

| Type | Details |
| ---- | ------- |
| **Automated backups** | Daily snapshot + transaction logs. Retention 0–35 days (0 disables them). Allows **point-in-time restore** to any second, usually up to ~5 minutes ago. |
| **Manual snapshots** | Kept until you delete them. Can be copied cross-region or shared cross-account. |
| Restore | Always creates a **new** DB instance with a new endpoint |
| AWS Backup | Central backup policies across services |

### Multi-AZ

- **Multi-AZ DB instance**: a **synchronous** standby in another AZ. It isn't readable. Automatic failover (typically 60–120 s) flips the DNS endpoint to the standby. Use it for **high availability**, not scaling.
- **Multi-AZ DB cluster** (MySQL/Postgres): 1 writer + 2 **readable** standbys across 3 AZs, faster failover (~35 s).
- Failover triggers: AZ outage, instance failure, OS patching, instance class change, manual reboot with failover.

### Read replicas

- **Asynchronous** copies (so there is replication lag) that serve read-only traffic. Use them to **scale reads**.
- Up to 15 for MySQL/MariaDB/PostgreSQL (and Aurora). They can be in the same region, another AZ or **another region** (DR).
- Each replica has its own endpoint, so the app must send reads there.
- A replica can be **promoted** to a standalone primary (for DR or migration).

| | Multi-AZ standby | Read replica |
| - | ---------------- | ------------ |
| Purpose | High availability | Read scaling / DR |
| Replication | Synchronous | Asynchronous |
| Readable | No (instance deployment) | Yes |
| Failover | Automatic | Manual promotion |
| Region | Same region | Same or cross-region |

### RDS use cases

- Traditional web/ERP/CRM apps that need joins, transactions and referential integrity.
- E-commerce orders, payments and inventory with strong consistency.
- Lift-and-shift of on-prem MySQL/PostgreSQL/Oracle/SQL Server.
- Reporting on read replicas.

### Example

```hcl
resource "aws_db_subnet_group" "db" {
  name       = "app-db"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "app" {
  identifier                  = "app-postgres"
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "appdb"
  username                    = "appadmin"
  manage_master_user_password = true # password generated and stored in Secrets Manager
  db_subnet_group_name        = aws_db_subnet_group.db.name
  vpc_security_group_ids      = [var.db_sg_id]
  publicly_accessible         = false
  multi_az                    = true
  backup_retention_period     = 7
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "app-postgres-final"
}

resource "aws_db_instance" "app_replica" {
  identifier          = "app-postgres-replica-1"
  replicate_source_db = aws_db_instance.app.identifier
  instance_class      = "db.t4g.micro"
  publicly_accessible = false
}
```

```bash
aws rds describe-db-instances \
  --query 'DBInstances[].[DBInstanceIdentifier,Engine,DBInstanceClass,MultiAZ,DBInstanceStatus,Endpoint.Address]' --output table
aws rds create-db-snapshot --db-instance-identifier app-postgres --db-snapshot-identifier app-pre-release
```

---

## Interview Q&A

**Q1. When would you choose DynamoDB over RDS?**
When access patterns are known and key-based, and you need predictable millisecond latency at very large or spiky scale with zero server management. Choose RDS for ad-hoc SQL, joins and complex transactions.

**Q2. Partition key vs sort key?**
The partition key decides which partition stores the item (it must spread load evenly). The sort key orders items within that partition and enables range queries. Together they form a composite primary key.

**Q3. What causes a hot partition, and how do you avoid it?**
A low-cardinality or skewed partition key (for example `status = ACTIVE`) sends most traffic to one partition. Use high-cardinality keys, or add a random/calculated suffix (write sharding).

**Q4. Query vs Scan in DynamoDB?**
A Query reads items with one partition key value (efficient). A Scan reads the whole table (expensive, avoid it in hot paths).

**Q5. Multi-AZ vs read replica?**
Multi-AZ provides synchronous standby HA with automatic failover. A read replica uses asynchronous replication to scale reads or for cross-region DR. You can use both together.

**Q6. How do you restore an RDS database to 10:15 this morning?**
Use point-in-time restore from automated backups (within the retention window). It creates a new instance, so you then switch the app's endpoint.

**Q7. How do you keep RDS credentials out of code?**
Use `manage_master_user_password` (Secrets Manager with rotation) or IAM database authentication, and have the app read the secret at runtime.

**Q8. Can you encrypt an existing unencrypted RDS instance?**
Not in place. Snapshot it, copy the snapshot with encryption enabled, then restore a new instance from the encrypted copy.
