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

## Collaborative Project: Team Deployment and Presentation

This lab is designed as a **team project**. Each team will fork the repo, deploy all 3 phases to AWS, and then present their migration to the class — explaining every decision as if they are in a real migration planning meeting with stakeholders.

The code is provided. **The real test is whether you can explain it.**

Anyone can run `terraform apply`. But can you explain to the CTO *why* the database is in a private subnet? Can you tell the security team *why* the container runs as a non-root user? Can you walk a new team member through a request from the customer's browser all the way to the database and back?

That is what companies are looking for in interviews — and that is what this exercise builds.

---

### How It Works

1. **Form teams** of 3-4 people
2. **Fork this repo** — each team works from their own copy
3. **Deploy all 3 phases** to your team's AWS environment
4. **Prepare a 15-minute presentation** answering the questions below
5. **Present to the class** — the instructor and other teams will ask follow-up questions

---

### Team Roles

Assign these roles within your team. Every member should understand *all* phases, but each role leads the discussion for their area:

| Role | Leads Discussion On | Key Questions They Must Answer |
|------|---------------------|-------------------------------|
| **Cloud Architect** | VPC design, subnets, security groups, overall architecture | "Why is the architecture designed this way? What are the trade-offs?" |
| **DevOps Engineer** | Terraform, EC2, EKS, deployment process | "How does the infrastructure get created? How do we deploy changes?" |
| **Database Engineer** | SQLite → RDS migration, data integrity, backups | "How did we migrate the data? What happens if the database goes down?" |
| **QA / Reliability Lead** | Testing, health checks, auto-scaling, disaster recovery | "How do we know the system is working? What happens when things fail?" |

> **Teams of 3:** Combine the Database Engineer and QA Lead roles.

---

### Presentation Structure (15 Minutes)

Your presentation should cover these sections:

#### 1. Architecture Walkthrough (5 minutes)

Draw or present the architecture for each phase. For each phase, trace a request from a customer's browser to the database and back. Show:
- Which components the request passes through
- Where traffic is encrypted
- Where authentication/authorization happens
- What happens if any single component fails

#### 2. Migration Decisions (5 minutes)

Explain the *why* behind key decisions:
- Why did we start with lift-and-shift instead of jumping to Kubernetes?
- Why PostgreSQL instead of keeping SQLite?
- Why is the ALB in a public subnet but the app servers are behind it?
- Why does the Dockerfile use Alpine instead of the full Node image?
- Why `runAsNonRoot` and `readOnlyRootFilesystem` in the Kubernetes deployment?

#### 3. Cost and Trade-offs (3 minutes)

Present a comparison:
- Estimated monthly cost for each phase
- What you gain at each phase vs. the added complexity
- Which phase gives the most value for the least effort?
- If NovaMart had a tight budget, where would you stop?

#### 4. What Would You Do Differently? (2 minutes)

Reflect on the migration:
- What would you change about this migration path?
- What is missing that a real production system would need?
- What would Phase 4 look like?

---

### Questions the Instructor Will Ask

Prepare for these — they are the same questions that come up in real cloud engineering interviews:

#### Phase 1: Rehost

| Question | What It Tests |
|----------|--------------|
| "Your EC2 instance just terminated at 2 AM. What happens to the data? What is the recovery process?" | Understanding of EBS, snapshots, and single points of failure |
| "The security group allows SSH from 0.0.0.0/0. Is that acceptable? What would you do in production?" | Security awareness — restricting SSH to specific IPs or using Session Manager |
| "The CEO asks for the rollback plan. If AWS does not work out, how do we go back to on-prem?" | Migration risk management |
| "How would you monitor this EC2 instance to know if it is healthy?" | Awareness of CloudWatch, health checks, alerting |

#### Phase 2: Re-Platform

| Question | What It Tests |
|----------|--------------|
| "Walk me through a request from a customer's browser to the database and back. Name every component it passes through." | End-to-end architecture understanding |
| "Why can't the internet reach the database directly? Show me exactly where that is enforced." | Security group chain comprehension |
| "It is Black Friday and traffic is 10x normal. One EC2 instance goes down. Walk me through what happens." | Understanding of ALB health checks, ASG, and RDS failover |
| "The database password is in the Terraform variables. Is that secure? What would you do instead?" | Secrets management awareness (AWS Secrets Manager, Parameter Store) |
| "Why did we move from SQLite to PostgreSQL? What specific problems does that solve?" | Database scaling knowledge — concurrent writes, network access, replication |

#### Phase 3: Re-Architect

| Question | What It Tests |
|----------|--------------|
| "What does `readOnlyRootFilesystem: true` do and why does it matter?" | Container security understanding |
| "The HPA is set to scale at 70% CPU. Why not 90%? Why not 50%?" | Understanding of scaling thresholds — headroom for traffic spikes |
| "I just deployed a broken container image. What happens? How does Kubernetes handle this?" | Rolling update strategy, readiness probes, rollback |
| "You have 10 pods running but the app is still slow. The CPU is at 30%. What is the bottleneck?" | Troubleshooting skills — database connections, network, memory, I/O |
| "What is the difference between a readiness probe and a liveness probe? Why do we need both?" | Kubernetes health check concepts |

#### Cross-Phase Questions

| Question | What It Tests |
|----------|--------------|
| "If you had to do this migration at a real company, would you skip Phase 1? Why or why not?" | Strategic thinking about migration risk |
| "Which phase gave NovaMart the most value for the least effort?" | Cost-benefit analysis |
| "A new developer joins the team. How would you onboard them to understand this infrastructure?" | Documentation, IaC readability, team processes |
| "The CTO wants to add a second application (e-commerce storefront) to this infrastructure. What would you change?" | Multi-service architecture thinking |
| "How would you set up CI/CD so that a git push automatically deploys to EKS?" | Awareness of the deployment pipeline gap — bridges to the CI/CD lab |

---

### Evaluation Criteria

Teams are not graded on whether the deployment works — they are evaluated on whether they can **explain and defend their architecture**:

| Criteria | What We Are Looking For |
|----------|------------------------|
| **Understanding** | Can every team member explain what each component does and why it exists? |
| **Communication** | Can they explain technical concepts clearly to a non-technical audience? |
| **Troubleshooting** | When asked "what happens if X fails?", can they trace through the system logically? |
| **Security Awareness** | Do they understand the security implications of each design choice? |
| **Cost Awareness** | Can they discuss trade-offs between cost, complexity, and reliability? |
| **Teamwork** | Did all members contribute? Can any member answer questions about any phase? |

---

### Tips for a Strong Presentation

1. **Draw your own diagrams.** Do not just show the ASCII diagrams from this README. Draw them on a whiteboard or in draw.io to prove you understand the architecture.
2. **Use the actual AWS console.** Show the running resources — the VPC, subnets, security groups, RDS instance, EKS pods. A live demo is more convincing than slides.
3. **Prepare for "what if" questions.** The strongest teams can answer questions about failure scenarios, scaling limits, and security threats.
4. **Admit what you do not know.** In real interviews and real jobs, "I am not sure, but I would investigate by checking X" is a better answer than guessing.
5. **Connect it to the business.** Remember — NovaMart is a retail chain. Frame your decisions in terms of uptime, customer impact, and cost, not just technical specs.

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
