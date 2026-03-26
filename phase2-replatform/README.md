# Phase 2: Re-Platform -- Add RDS PostgreSQL and Load Balancing

## What Is Re-Platforming?

Re-platforming (sometimes called "lift-tinker-and-shift") means migrating your application to the cloud while making **targeted upgrades** to take advantage of cloud-native services. You are not rewriting the application -- you are swapping out specific components for managed alternatives.

**NovaMart analogy:** You are moving apartments AND upgrading your old tube TV to a smart TV. The living room layout is the same, but now you have Netflix. The couch, the coffee table, the bookshelf -- all the same. But the TV is better, and it came with the apartment.

In this phase, we replace SQLite with **Amazon RDS PostgreSQL** (managed database) and add an **Application Load Balancer** to distribute traffic across multiple app servers.

---

## What Changes in This Phase

| Aspect            | Phase 1 (EC2)                   | Phase 2 (RDS + ALB)                          |
|-------------------|----------------------------------|-----------------------------------------------|
| Database          | SQLite file on EC2               | RDS PostgreSQL (managed, backed up)           |
| Load Balancing    | None                             | Application Load Balancer                     |
| Instances         | 1 EC2                            | 2 EC2 (Auto Scaling Group, min 1 / max 3)    |
| High Availability | None                             | Multi-AZ option for RDS                       |
| Backup            | Manual EBS snapshots             | Automated daily RDS backups (7-day retention) |

---

## Why PostgreSQL Instead of SQLite?

SQLite is a fantastic embedded database, but it has serious limitations for production workloads:

- **Single writer at a time** -- SQLite locks the entire database file during writes. Two users updating inventory simultaneously? One has to wait.
- **No network access** -- SQLite runs as a library inside your app process. It cannot be accessed over the network, which means your database MUST live on the same machine as your app.
- **No user management** -- There are no database users, no roles, no permissions. Anyone who can read the file can read everything.
- **No replication** -- If the EC2 instance dies, your SQLite file dies with it (unless you have EBS snapshots, which are manual and point-in-time).

PostgreSQL on RDS solves all of these:

- **Concurrent writes** with row-level locking
- **Network accessible** from any app server in the VPC
- **Full user/role management** with fine-grained permissions
- **Automated backups** with point-in-time recovery
- **Optional Multi-AZ** for automatic failover

---

## Architecture

```
                          Internet
                             |
                    +--------+--------+
                    |   ALB (port 80) |
                    | novamart-alb-sg |
                    +--------+--------+
                             |
              +--------------+--------------+
              |                             |
     +--------+--------+          +--------+--------+
     | EC2 (AZ-a)      |          | EC2 (AZ-b)      |
     | Public Subnet    |          | Public Subnet    |
     | 10.0.1.0/24      |          | 10.0.2.0/24      |
     | novamart-app-sg  |          | novamart-app-sg  |
     | (port 3000)      |          | (port 3000)      |
     +--------+---------+          +--------+---------+
              |                             |
              +--------------+--------------+
                             |
                    +--------+--------+
                    | RDS PostgreSQL  |
                    | Private Subnets |
                    | 10.0.10.0/24    |
                    | 10.0.11.0/24    |
                    | novamart-rds-sg |
                    | (port 5432)     |
                    +-----------------+
```

---

## Step 1: Review the Terraform Changes

Before applying anything, take a few minutes to read through `terraform/main.tf`. Here is what is new compared to Phase 1:

### New Resources

1. **Second public subnet** (`aws_subnet.public_b`) -- ALBs require subnets in at least two Availability Zones.
2. **Two private subnets** (`aws_subnet.private_a`, `private_b`) -- RDS lives here, unreachable from the internet.
3. **Three security groups** -- ALB, App, and RDS, each only allowing traffic from the layer above.
4. **RDS PostgreSQL** (`aws_db_instance.novamart`) -- Managed database with automated backups.
5. **Application Load Balancer** (`aws_lb.novamart`) -- Distributes HTTP traffic across EC2 instances.
6. **Target Group + Listener** -- Routes ALB traffic to port 3000 with `/health` checks.
7. **Launch Template** -- Defines the EC2 configuration with user data that connects to RDS.
8. **Auto Scaling Group** -- Maintains 2 instances (scales between 1 and 3).

### The Security Group Chain

This is the most important concept to understand:

```
Internet --> ALB SG (port 80 from 0.0.0.0/0)
                --> App SG (port 3000 from ALB SG only)
                       --> RDS SG (port 5432 from App SG only)
```

Each layer only talks to the next. The internet cannot directly reach your app servers or your database. This is **defense in depth**.

---

## Step 2: Set Your Variables

Create a `terraform.tfvars` file in the `terraform/` directory:

```hcl
key_pair_name = "your-key-pair-name"
db_password   = "YourStr0ngP@ssword!"
```

**Important:** Choose a strong database password. RDS enforces a minimum of 8 characters. Do NOT commit this file to version control.

Optional overrides:

```hcl
aws_region        = "us-east-1"      # default
instance_type     = "t3.micro"       # default
db_instance_class = "db.t3.micro"    # default
db_username       = "novamart_admin" # default
```

---

## Step 3: Initialize and Apply

```bash
cd phase2-replatform/terraform

# Download providers
terraform init

# Preview what will be created
terraform plan

# Apply (RDS takes 5-10 minutes to provision)
terraform apply
```

Note the outputs after apply completes:
- `application_url` -- the ALB URL to access NovaMart
- `rds_endpoint` -- the RDS connection string

---

## Step 4: Run the Database Migration

The user data script automatically runs the migration when each EC2 instance boots. However, if you want to run it manually or verify it worked:

```bash
# SSH into one of the EC2 instances
ssh -i your-key.pem ec2-user@<instance-public-ip>

# Check the setup log
cat /var/log/novamart-setup.log

# Verify the database migration
export PGHOST=<rds-endpoint-without-port>
export PGPORT=5432
export PGDATABASE=novamart
export PGUSER=novamart_admin
export PGPASSWORD=<your-db-password>

psql -c "SELECT count(*) FROM products;"
# Expected: 15
```

---

## Step 5: Verify the ALB

```bash
# Get the ALB URL from Terraform output
ALB_URL=$(terraform output -raw application_url)

# Test the health endpoint
curl $ALB_URL/health

# Test the products API
curl $ALB_URL/api/products

# Make multiple requests and observe the responses
# (you may see different instance IDs in the response)
for i in {1..5}; do
  curl -s $ALB_URL/health | jq .
  echo "---"
done
```

---

## Step 6: Test High Availability

This is where re-platforming pays off. Try these experiments:

### Experiment A: Stop One EC2 Instance

1. Go to the EC2 console and stop one of the two app servers.
2. Wait 30 seconds and hit the ALB URL again -- it still works! The ALB routes traffic to the healthy instance.
3. Watch the Auto Scaling Group launch a replacement instance within a few minutes.

### Experiment B: Check RDS Automated Backups

1. Go to the RDS console and click on `novamart-inventory-db`.
2. Click the "Maintenance & backups" tab.
3. Notice the automated backup window and 7-day retention period.
4. You get point-in-time recovery for free -- try restoring to any second in the last 7 days.

### Experiment C: Enable Multi-AZ (Optional)

In `main.tf`, uncomment the `multi_az = true` line on the RDS instance and run `terraform apply`. This creates a standby replica in a different AZ. If the primary fails, RDS automatically fails over -- typically in under 60 seconds.

---

## Understanding Security Groups (The Firewall Chain)

```
+------------------+     +------------------+     +------------------+
|   ALB SG         |     |   App SG         |     |   RDS SG         |
|                  |     |                  |     |                  |
| IN:  80 from     | --> | IN:  3000 from   | --> | IN:  5432 from   |
|      0.0.0.0/0   |     |      ALB SG      |     |      App SG      |
|                  |     |                  |     |                  |
| OUT: all         |     | IN:  22 (SSH)    |     | OUT: (default    |
|                  |     |      0.0.0.0/0   |     |      deny)       |
|                  |     | OUT: all         |     |                  |
+------------------+     +------------------+     +------------------+
```

**Key insight:** Security groups reference OTHER security groups, not IP addresses. The App SG says "allow port 3000 from the ALB security group." This means:

- If you add a new ALB, it automatically gets access (if it uses the ALB SG).
- If you remove the ALB SG from a resource, it immediately loses access.
- You never have to manage IP allow-lists.

This is one of the most powerful patterns in AWS networking.

---

## Cost Awareness

Estimated hourly costs for this lab (us-east-1):

| Resource              | Hourly Cost  | Notes                          |
|-----------------------|-------------|--------------------------------|
| 2x t3.micro EC2      | ~$0.021     | $0.0104/hr each                |
| RDS db.t3.micro       | ~$0.018     | Single-AZ                     |
| ALB                   | ~$0.023     | + $0.008 per LCU-hour         |
| **Total**             | **~$0.062** | **~$1.49/day**                 |

Remember to destroy resources when you are done!

---

## Cleanup

```bash
cd phase2-replatform/terraform
terraform destroy
```

Type `yes` when prompted. RDS deletion takes a few minutes.

---

## What You Learned

- How to set up **RDS PostgreSQL** as a managed database replacement for SQLite
- How to configure an **Application Load Balancer** for traffic distribution
- How to use **Auto Scaling Groups** to maintain multiple EC2 instances
- How **security group chaining** creates defense-in-depth network security
- How to migrate a database schema from SQLite to PostgreSQL
- The difference between public subnets (internet-facing) and private subnets (internal only)

## Next Steps

In **Phase 3 (Re-Architect)**, we will break the monolith into microservices, add an API Gateway, and use DynamoDB for session management. The application architecture will become truly cloud-native.
