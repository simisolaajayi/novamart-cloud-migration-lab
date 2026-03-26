# Cloud Migration Lab -- NovaMart Retail Inventory System

## The Scenario

You are the lead cloud engineer at **NovaMart**, a mid-size retail chain with 12 store locations across the United States. NovaMart's inventory management system runs on a pair of aging Dell PowerEdge servers tucked inside a network closet at the company's Houston headquarters. The system tracks every product across all 12 stores, manages stock levels, and processes restock orders.

The problems started piling up:

- **Black Friday Outage.** Last December, during the busiest shopping day of the year, both servers maxed out under the holiday traffic surge. The inventory system went down for 4 hours. Store associates could not check stock, process orders, or transfer products between locations. The outage cost NovaMart an estimated **$180,000 in lost sales**.

- **Hardware Refresh Quote.** The servers are 7 years old and out of warranty. The IT team got a quote to replace them: **$500,000** for new hardware, licensing, and installation -- with a 12-week lead time.

- **Disaster Recovery.** The current backup strategy is a manual weekly backup to a USB external hard drive that sits on a shelf next to the servers. There is no offsite copy. If the closet floods or the drive fails, everything is gone.

The CTO has approved migrating the inventory system to AWS. The migration will happen in 3 phases to minimize risk, allow the team to learn as they go, and keep the business running throughout.

This lab walks you through that journey -- from running the application on-premises to deploying it on a fully scalable, resilient AWS architecture.

---

## What You Will Learn

- The 6 R's of cloud migration (Rehost, Re-platform, Refactor, Repurchase, Retire, Retain)
- How to assess an application for cloud readiness
- VPC design with public and private subnets
- Deploying applications on EC2 (lift-and-shift)
- Migrating databases from SQLite to Amazon RDS PostgreSQL
- Adding load balancing with an Application Load Balancer
- Containerizing applications with Docker
- Deploying to Amazon EKS with auto-scaling
- Infrastructure as Code with Terraform
- Cost comparison across migration phases

---

## Architecture Overview

### Current State: On-Premises

```
                     +-------------------------------------------+
                     |         Houston HQ Server Closet          |
                     |                                           |
  Users ----------> |   [ Dell PowerEdge Server ]                |
  (12 stores)       |   |  Express.js App (port 3000)  |        |
                     |   |  SQLite Database (on disk)   |        |
                     |   +-----------------------------+         |
                     |                                           |
                     |   [ USB External Drive ]                  |
                     |     Manual weekly backup                  |
                     +-------------------------------------------+

  Single point of failure. No redundancy. No auto-scaling.
```

### Phase 1: Rehost (Lift and Shift)

```
                     +-- AWS VPC (10.0.0.0/16) ------------------+
                     |                                            |
                     |  +-- Public Subnet (10.0.1.0/24) -------+ |
                     |  |                                       | |
  Users ----------> |  |  [ EC2 Instance ]                     | |
  (Internet)        |  |  |  Express.js App (port 3000) |      | |
                     |  |  |  SQLite Database (on EBS)   |      | |
                     |  |  +----------------------------+       | |
                     |  +---------------------------------------+ |
                     |                                            |
                     |  EBS Snapshots for backup                  |
                     +--------------------------------------------+

  Same app, better infrastructure. Automated backups via EBS.
```

### Phase 2: Re-Platform

```
                     +-- AWS VPC (10.0.0.0/16) -----------------------+
                     |                                                 |
                     |  +-- Public Subnets ---+                        |
  Users ----------> |  |  [ ALB ]            |                        |
  (Internet)        |  +--------|------------+                        |
                     |           |                                     |
                     |  +-- Private Subnets --|------------------------+
                     |  |        v            v                        |
                     |  |  [ EC2 App 1 ] [ EC2 App 2 ]                |
                     |  |        |            |                        |
                     |  |        +-----+------+                        |
                     |  |              v                               |
                     |  |  [ RDS PostgreSQL - Multi-AZ ]              |
                     |  |    Primary  <-->  Standby                   |
                     |  +--------------------------------------------- +
                     +--------------------------------------------------+

  Load-balanced. Managed database. Multi-AZ resilience.
```

### Phase 3: Re-Architect

```
                     +-- AWS VPC (10.0.0.0/16) -----------------------+
                     |                                                 |
                     |  +-- Public Subnets ---+                        |
  Users ----------> |  |  [ ALB / Ingress ]  |                        |
  (Internet)        |  +--------|------------+                        |
                     |           |                                     |
                     |  +-- Private Subnets --|------------------------+
                     |  |        v                                     |
                     |  |  [ EKS Cluster ]                            |
                     |  |  | Pod 1 | Pod 2 | Pod 3 | ... |           |
                     |  |  | (HPA auto-scales pods)      |           |
                     |  |        |                                     |
                     |  |        v                                     |
                     |  |  [ RDS PostgreSQL - Multi-AZ ]              |
                     |  +---------------------------------------------- +
                     +--------------------------------------------------+

  Container orchestration. Horizontal pod auto-scaling. Self-healing.
```

---

## Understanding Cloud Migration (For Beginners)

### The 6 R's of Migration

When companies move workloads to the cloud, there are six common strategies -- often called the "6 R's." Here is what each one means, with a NovaMart analogy to make it concrete:

| Strategy | What It Means | NovaMart Analogy |
|----------|--------------|------------------|
| **Rehost** | Move the application as-is to the cloud with minimal changes. | Moving your furniture to a new apartment without changing anything -- same couch, same layout, different building. |
| **Re-platform** | Move to the cloud and swap out a few components for managed services. | Moving AND upgrading your old tube TV to a smart TV while you are at it -- mostly the same stuff, but you take advantage of what the new place offers. |
| **Refactor** | Re-architect the application to be cloud-native, taking full advantage of cloud services. | Renovating the entire apartment while moving in -- new layout, new furniture, built-in smart home system. |
| **Repurchase** | Drop the existing solution and buy a SaaS replacement. | Selling all your furniture and buying everything new from IKEA. |
| **Retire** | Turn off applications that are no longer needed. | Throwing away the boxes of stuff in your garage that you have not opened in 5 years. |
| **Retain** | Keep some workloads on-premises for now (regulatory, technical, or business reasons). | Leaving some things in the old apartment because the lease is not up yet. |

In this lab, NovaMart follows a progressive path through the first three R's: **Rehost** (Phase 1), **Re-platform** (Phase 2), and **Refactor** (Phase 3).

### Why Not Jump Straight to Phase 3?

It is tempting to skip ahead to the fully modernized architecture, but there are good reasons to take a phased approach:

1. **Risk reduction.** Each phase is a smaller, testable change. If something breaks, the blast radius is limited.
2. **Team learning.** The NovaMart team has never used AWS. Phase 1 lets them learn EC2, VPCs, and security groups before tackling Kubernetes.
3. **Business continuity.** The stores need the inventory system every day. A phased approach means shorter maintenance windows and faster rollback if needed.
4. **Quick wins.** Phase 1 already gives NovaMart automated backups and the ability to resize capacity -- solving the two most urgent problems (disaster recovery and the Black Friday outage) without a full re-architecture.

---

## Prerequisites

Before starting, make sure you have the following installed and configured:

- **AWS Account** with permissions to create VPCs, EC2 instances, RDS databases, EKS clusters, and IAM roles
- **AWS CLI** configured with your credentials (`aws configure`)
- **Terraform** v1.5 or later
- **Docker** and **Docker Compose**
- **kubectl** (for Phase 3)
- **Node.js 18+** and npm (for local testing)

---

## Step 0: Explore the On-Premises Application

Before migrating anything, you need to understand what you are working with. NovaMart's inventory system is a monolithic Node.js application backed by a SQLite database. Let's run it locally and see how it works.

### Run Locally

```bash
cd on-premises/app
npm install
npm start
```

The server will start on port 3000. You should see:

```
NovaMart Inventory System running on port 3000
Environment: on-premises
```

### Test the API

Open a new terminal and try these commands:

**Check system health:**

```bash
curl http://localhost:3000/health | jq
```

Expected output:

```json
{
  "service": "NovaMart Inventory System",
  "version": "1.0.0",
  "environment": "on-premises",
  "database": "connected",
  "uptime": 5.123
}
```

**List all products:**

```bash
curl http://localhost:3000/api/products | jq
```

**Filter products by category:**

```bash
curl "http://localhost:3000/api/products?category=Electronics" | jq
```

**Get inventory summary (shows low-stock items):**

```bash
curl http://localhost:3000/api/inventory | jq
```

**Restock a product:**

```bash
curl -X POST http://localhost:3000/api/inventory/restock \
  -H "Content-Type: application/json" \
  -d '{"product_id": 11, "quantity": 50}' | jq
```

**View store locations:**

```bash
curl http://localhost:3000/api/locations | jq
```

### Run the Tests

```bash
cd on-premises/app
npm test
```

All 12 tests should pass. The tests use an in-memory SQLite database, so they do not affect any persistent data.

### Run with Docker Compose

To simulate the full on-premises environment:

```bash
cd on-premises
docker compose up --build
```

### Understand the Problem

Now that you have seen the application, consider the limitations:

| Limitation | Impact |
|-----------|--------|
| **Single server** | If it goes down, all 12 stores lose inventory access |
| **No load balancing** | One server handles all traffic -- no way to distribute load |
| **SQLite database** | Not designed for concurrent writes from multiple stores |
| **No auto-scaling** | Cannot add capacity during holiday traffic spikes |
| **Manual backups** | Weekly USB backups mean up to 7 days of data loss in a disaster |
| **No monitoring** | Nobody knows the system is down until a store manager calls IT |

These are exactly the problems the migration will solve.

---

## Phase 1: Rehost -- Lift and Shift to EC2

> Detailed instructions: `phase1-rehost/README.md`

The first phase moves the application to AWS with minimal changes. The goal is to get off the aging hardware and into a proper data center as quickly as possible.

### What Changes

- Application runs on an EC2 instance instead of the Dell server
- Database files are stored on an EBS volume (with automated snapshots)
- Server is inside a VPC with security groups controlling access
- Infrastructure is defined in Terraform (repeatable, version-controlled)

### What Stays the Same

- The application code is identical -- same Express.js app, same SQLite database
- Same single-server architecture (no load balancing yet)
- Same port (3000)

### Key Terraform Resources

- `aws_vpc` -- isolated network for NovaMart
- `aws_subnet` -- public subnet for the EC2 instance
- `aws_security_group` -- allows HTTP (3000) and SSH (22) inbound
- `aws_instance` -- the EC2 instance running the app
- `aws_ebs_volume` -- persistent storage for the SQLite database

### After This Phase

NovaMart gets automated backups (EBS snapshots), the ability to resize the instance if traffic spikes, and infrastructure that can be rebuilt in minutes instead of weeks. But there is still a single point of failure.

---

## Phase 2: Re-Platform -- Add RDS and Load Balancing

> Detailed instructions: `phase2-replatform/README.md`

Phase 2 swaps out SQLite for Amazon RDS PostgreSQL and adds an Application Load Balancer in front of multiple EC2 instances. This is where NovaMart starts to see real resilience improvements.

### What Changes

- SQLite is replaced by RDS PostgreSQL (Multi-AZ for high availability)
- An Application Load Balancer distributes traffic across multiple EC2 instances
- Application code is updated with a small database adapter to use PostgreSQL
- EC2 instances move to private subnets (only the ALB is public-facing)

### Key Improvements

- **Database resilience:** RDS Multi-AZ means automatic failover if the primary database goes down
- **Load distribution:** Multiple app servers share the traffic
- **Automated backups:** RDS handles daily backups and point-in-time recovery
- **Better security:** App servers are in private subnets, not directly accessible from the internet

### After This Phase

A single EC2 instance failing no longer takes down the system. The database has automated backups with point-in-time recovery. The Black Friday problem is partially solved (more instances behind the ALB), but scaling is still manual.

---

## Phase 3: Re-Architect -- Containerize and Deploy to EKS

> Detailed instructions: `phase3-rearchitect/README.md`

Phase 3 containerizes the application and deploys it to Amazon EKS (Elastic Kubernetes Service). This is the fully modernized architecture.

### What Changes

- Application is packaged as a Docker container with an optimized multi-stage Dockerfile
- Containers run as pods in an EKS cluster
- Horizontal Pod Autoscaler (HPA) automatically adds or removes pods based on CPU utilization
- Kubernetes manifests define the desired state -- the cluster self-heals if a pod crashes

### Key Improvements

- **Auto-scaling:** HPA scales pods up during Black Friday and scales them down after
- **Self-healing:** If a pod crashes, Kubernetes automatically replaces it
- **Fast deployments:** Rolling updates mean zero-downtime deployments
- **Resource efficiency:** Multiple containers share the same EC2 nodes, reducing cost per request

### After This Phase

NovaMart has a production-grade, auto-scaling, self-healing system. The Black Friday outage scenario is fully addressed. Deployments take seconds instead of hours. The team can focus on features instead of firefighting infrastructure.

---

## Migration Comparison Table

| Aspect | On-Prem | Phase 1 (EC2) | Phase 2 (RDS+ALB) | Phase 3 (EKS) |
|--------|---------|---------------|---------------------|----------------|
| **Compute** | Single server | Single EC2 | Multiple EC2 behind ALB | Auto-scaling pods |
| **Database** | SQLite on disk | SQLite on EBS | RDS PostgreSQL (Multi-AZ) | RDS PostgreSQL |
| **High Availability** | None | None | ALB + Multi-AZ RDS | HPA + Multi-AZ |
| **Disaster Recovery** | Manual USB backup | EBS snapshots | Automated RDS backups | Automated + GitOps |
| **Scaling** | Buy new hardware | Resize instance | Add instances to ALB | Auto-scale pods |
| **Deploy Time** | Hours (manual) | Minutes (Terraform) | Minutes (Terraform) | Seconds (kubectl) |
| **Monthly Cost Est.** | $500K/3yr hardware | ~$50/mo | ~$150/mo | ~$200/mo |

---

## Cleanup

When you are finished with the lab, tear down resources in reverse order to avoid dependency errors:

```bash
# Phase 3 (if completed)
cd phase3-rearchitect/terraform
terraform destroy -auto-approve

# Phase 2 (if completed)
cd ../../phase2-replatform/terraform
terraform destroy -auto-approve

# Phase 1 (if completed)
cd ../../phase1-rehost/terraform
terraform destroy -auto-approve
```

Stop the local Docker environment:

```bash
cd on-premises
docker compose down -v
```

---

## What's Next?

Once you have completed this migration lab, explore these related labs to continue building your cloud skills:

- **CI/CD Pipelines** -- Automate testing and deployment with GitHub Actions
- **Container Security** -- Scan images for vulnerabilities and enforce policies
- **GitOps with ArgoCD** -- Manage Kubernetes deployments declaratively from Git
- **Logging and Observability** -- Add centralized logging, metrics, and alerting

---

## Project Structure

```
cloud-migration-lab/
|-- README.md                       # This file
|-- on-premises/
|   |-- docker-compose.yml          # Simulates the on-prem environment
|   |-- app/
|   |   |-- server.js               # NovaMart Inventory API (Express.js)
|   |   |-- package.json            # Node.js dependencies
|   |   |-- Dockerfile              # Container image for the app
|   |   |-- __tests__/
|   |       |-- app.test.js         # Jest test suite (12 tests)
|   |-- database/
|       |-- init.sql                # Reference SQL schema and seed data
|-- phase1-rehost/                  # (Phase 1 Terraform and docs)
|-- phase2-replatform/              # (Phase 2 Terraform and docs)
|-- phase3-rearchitect/             # (Phase 3 Kubernetes manifests and docs)
```
