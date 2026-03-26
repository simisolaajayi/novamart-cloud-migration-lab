# Phase 1: Rehost — Lift and Shift to EC2

## What Is Rehosting?

Rehosting (also called "lift and shift") is the simplest migration strategy in the AWS 7 R's framework. You take your existing application — code, configuration, and all — and move it onto cloud infrastructure with minimal changes.

Think of it this way: **It's like moving your furniture to a new apartment without changing anything. Same sofa, same TV, same layout — just a different building with better plumbing and electricity.**

For NovaMart, this means taking the exact same Node.js inventory management application that runs on a physical server in the office and deploying it on an EC2 instance in AWS. The application code does not change at all.

### Why Start Here?

- **Low risk:** Nothing about the application changes, so there's very little that can break.
- **Fast:** You can be running in the cloud within hours, not weeks.
- **Foundation:** It gets you into AWS, where you can then optimize incrementally.
- **Learning:** You get hands-on with core AWS services (VPC, EC2, Security Groups).

---

## What Changes in This Phase

| Aspect | Before (On-Prem) | After (EC2) |
|---------|-------------------|-------------|
| Server | Dell PowerEdge in closet | t3.micro EC2 instance |
| Network | Office LAN | AWS VPC with public subnet |
| Storage | Local hard drive | EBS gp3 (encrypted) |
| Access | Walk to server room | SSH over internet |
| Backup | Manual USB drive | EBS snapshots (can automate) |
| Cost | Upfront hardware purchase | Pay-per-hour (~$0.0104/hr) |

## What Stays the Same

- Same application code (zero changes)
- Same SQLite database (file-based, on local disk)
- Same single-server architecture
- Same scaling limitations (but now you can resize the instance!)

---

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              AWS Cloud (us-east-1)          │
                    │                                             │
                    │  ┌──────────────────────────────────────┐   │
                    │  │         VPC: 10.0.0.0/16             │   │
                    │  │                                      │   │
Internet ───────────┼──┤  ┌── Internet Gateway ──┐            │   │
                    │  │  │                      │            │   │
                    │  │  │  ┌────────────────────────────┐   │   │
                    │  │  │  │  Public Subnet: 10.0.1.0/24│   │   │
                    │  │  │  │                            │   │   │
                    │  │  │  │  ┌──────────────────────┐  │   │   │
                    │  │  │  │  │  EC2 Instance         │  │   │   │
                    │  │  │  │  │  (t3.micro)           │  │   │   │
                    │  │  │  │  │                       │  │   │   │
                    │  │  │  │  │  NovaMart App (:3000) │  │   │   │
                    │  │  │  │  │  SQLite DB            │  │   │   │
                    │  │  │  │  │  EBS gp3 20GB         │  │   │   │
                    │  │  │  │  └──────────────────────┘  │   │   │
                    │  │  │  │                            │   │   │
                    │  │  │  │  Security Group:           │   │   │
                    │  │  │  │    Inbound: 22, 3000       │   │   │
                    │  │  │  │    Outbound: All           │   │   │
                    │  │  │  └────────────────────────────┘   │   │
                    │  │  │                                    │   │
                    │  └──┴────────────────────────────────────┘   │
                    │                                             │
                    └─────────────────────────────────────────────┘
```

---

## Step-by-Step Instructions

### Step 1: Review the Terraform Configuration

Before deploying anything, take time to read and understand the infrastructure code. Open each file and make sure you understand what every resource does.

**`terraform/main.tf`** — The main infrastructure definition:

- **VPC** (`aws_vpc.novamart`): A Virtual Private Cloud is your isolated network in AWS. Think of it as your own private data center. The CIDR block `10.0.0.0/16` gives us 65,536 IP addresses to work with.

- **Internet Gateway** (`aws_internet_gateway.novamart`): This connects your VPC to the public internet. Without it, nothing in your VPC can reach the outside world (or be reached from it).

- **Public Subnet** (`aws_subnet.public`): A subdivision of the VPC where we place our EC2 instance. The `map_public_ip_on_launch = true` setting means instances here automatically get a public IP.

- **Route Table** (`aws_route_table.public`): Defines that traffic destined for `0.0.0.0/0` (anywhere on the internet) should go through the Internet Gateway.

- **Security Group** (`aws_security_group.novamart_app`): A virtual firewall. We allow inbound traffic on port 3000 (our app) and port 22 (SSH). All outbound traffic is allowed.

- **EC2 Instance** (`aws_instance.novamart_app`): The actual virtual server. It uses Amazon Linux 2023, a t3.micro instance type, and runs our user data script on first boot.

**`terraform/variables.tf`** — Input variables that make the configuration reusable.

**`terraform/outputs.tf`** — Values displayed after `terraform apply` (like the server's IP address).

> **Discussion:** Look at the security group. Why might allowing SSH from `0.0.0.0/0` be a bad idea in production? What would you use instead?

---

### Step 2: Create a Key Pair

You need an SSH key pair to connect to the EC2 instance. Run this command to create one:

```bash
# Create a key pair and save the private key locally
aws ec2 create-key-pair \
  --key-name novamart-keypair \
  --query 'KeyMaterial' \
  --output text > novamart-keypair.pem

# Set proper permissions on the key file
chmod 400 novamart-keypair.pem
```

> **Note:** Keep this `.pem` file safe. If you lose it, you will not be able to SSH into your instance. Never commit it to git.

---

### Step 3: Initialize and Plan

Navigate to the Terraform directory and initialize the project:

```bash
cd phase1-rehost/terraform

# Download the AWS provider plugin
terraform init

# Preview what Terraform will create (no changes are made yet)
terraform plan -var="key_pair_name=novamart-keypair"
```

**Read the plan output carefully.** You should see Terraform wants to create:
- 1 VPC
- 1 Internet Gateway
- 1 Subnet
- 1 Route Table + Association
- 1 Security Group
- 1 EC2 Instance

> **Discussion:** Why do we run `plan` before `apply`? What could go wrong if we skipped this step?

---

### Step 4: Apply the Infrastructure

Once you're satisfied with the plan, deploy it:

```bash
terraform apply -var="key_pair_name=novamart-keypair"
```

Type `yes` when prompted. Terraform will create all the resources. This typically takes 1-2 minutes.

When complete, you will see the outputs:

```
Outputs:

application_url = "http://X.X.X.X:3000"
instance_public_dns = "ec2-X-X-X-X.compute-1.amazonaws.com"
instance_public_ip = "X.X.X.X"
security_group_id = "sg-xxxxxxxxx"
vpc_id = "vpc-xxxxxxxxx"
```

**Save the `instance_public_ip` — you will need it for the next steps.**

---

### Step 5: Verify the Deployment

SSH into the instance to check that the application started correctly:

```bash
# SSH into the instance
ssh -i novamart-keypair.pem ec2-user@$(terraform output -raw instance_public_ip)

# Check if the app service is running
sudo systemctl status novamart

# View the application logs
sudo journalctl -u novamart --no-pager -n 50

# Check cloud-init log for any boot errors
sudo tail -100 /var/log/cloud-init-output.log
```

> **Tip:** The user data script runs during first boot and may take a few minutes. If the app is not running yet, wait and check again.

---

### Step 6: Test the Application

Run the same tests you ran in Step 0 (on-premises), but now against your EC2 instance:

```bash
# Store the IP for convenience
export EC2_IP=$(terraform output -raw instance_public_ip)

# Health check
curl http://$EC2_IP:3000/health

# Get all inventory items
curl http://$EC2_IP:3000/api/inventory

# Add a new item
curl -X POST http://$EC2_IP:3000/api/inventory \
  -H "Content-Type: application/json" \
  -d '{"name": "Cloud Widget", "quantity": 100, "price": 29.99}'

# Verify it was added
curl http://$EC2_IP:3000/api/inventory
```

**You should get the exact same responses as when running locally.** That's the whole point of lift-and-shift — the application behaves identically.

> **Discussion:** Open the app URL in your browser too. Notice anything different in the UI? (Hint: check if the ENVIRONMENT variable is displayed.)

---

## What We Gained

By completing Phase 1, NovaMart now has:

- **No hardware maintenance** — AWS manages the physical servers, power, cooling, and networking.
- **Encrypted storage** — The EBS volume is encrypted at rest, something that was not configured on-prem.
- **Vertical scaling** — Need more CPU? Stop the instance, change the type to `t3.medium` or `t3.large`, and start it again. Takes minutes, not weeks of procurement.
- **Foundation for Phase 2** — The VPC, subnet, and security group we created will be reused and extended.
- **Infrastructure as Code** — Everything is defined in Terraform. You can destroy and recreate the entire environment in minutes.

## What's Still Missing

- **Single point of failure** — If the EC2 instance dies, the app goes down with it. There is no redundancy.
- **SQLite can't scale** — File-based database locks on writes. Two users writing at the same time will cause errors.
- **No load balancing** — All traffic hits one server. There is no way to distribute load.
- **No auto-scaling** — Traffic spikes during sales events will overwhelm the single instance.
- **Data loss risk** — The SQLite database lives on the instance. If the instance is terminated, the data is gone.

**Phase 2 (Replatform) will address all of these issues** by introducing RDS, Application Load Balancer, and Auto Scaling.

---

## Cleanup

When you are done exploring, destroy the infrastructure to avoid ongoing charges:

```bash
terraform destroy -var="key_pair_name=novamart-keypair"
```

Type `yes` when prompted. Terraform will remove all resources it created.

Also delete the key pair:

```bash
aws ec2 delete-key-pair --key-name novamart-keypair
rm novamart-keypair.pem
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `terraform init` | Download providers and initialize |
| `terraform plan` | Preview changes |
| `terraform apply` | Create/update infrastructure |
| `terraform output` | Show output values |
| `terraform destroy` | Delete all resources |
| `ssh -i key.pem ec2-user@IP` | Connect to the instance |
| `sudo systemctl status novamart` | Check app status on instance |
| `sudo journalctl -u novamart -f` | Stream app logs on instance |
