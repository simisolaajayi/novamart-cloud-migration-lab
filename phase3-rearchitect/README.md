# Phase 3: Re-Architect -- Containerize and Deploy to EKS

## What Is Re-Architecting?

Re-architecting means redesigning the application to take full advantage of cloud-native services. Instead of running our Node.js app directly on EC2 instances, we package it as a Docker container and deploy it to Amazon EKS (Elastic Kubernetes Service). This gives us automated scaling, self-healing, and a consistent deployment model.

> **NovaMart Analogy:** You've moved apartments twice. Now you're renovating -- knocking down walls, adding smart home tech, and installing a system that automatically adjusts the heating based on how many people are home. It's the most work, but the apartment becomes a smart home.

---

## What Changes in This Phase

| Aspect | Phase 2 (RDS + ALB) | Phase 3 (EKS) |
|--------|---------------------|----------------|
| Compute | EC2 instances (ASG) | Kubernetes pods (auto-scaled) |
| Packaging | Code on EC2 | Docker container image |
| Scaling | ASG (minutes) | HPA (seconds) |
| Deployment | User data script | kubectl apply / GitOps |
| Resilience | ALB health checks | K8s readiness/liveness probes + self-healing |
| Config | Env vars on EC2 | ConfigMaps + Secrets |

---

## Architecture

```
                         +-----------------------------+
                         |        EKS Cluster          |
                         |  (novamart-eks-cluster)     |
Internet                 |                             |
   |                     |  +-------+ +-------+ +--+  |
   v                     |  | Pod 1 | | Pod 2 | |Pod3| |
LoadBalancer Service ------>| nova  | | nova  | |nova| |
  (port 80 -> 3000)     |  | mart  | | mart  | |mart| |
                         |  +---+---+ +---+---+ +-+--+ |
                         |      |         |        |    |
                         +------|---------|--------|----+
                                |         |        |
                                v         v        v
                         +-----------------------------+
                         |   RDS PostgreSQL             |
                         |   (from Phase 2)             |
                         +-----------------------------+

HPA monitors CPU usage --> scales pods between 2 and 10
```

---

## Prerequisites

- Docker installed locally
- kubectl installed
- AWS CLI configured
- A DockerHub account (free tier is fine)
- (Optional) Terraform >= 1.5 if creating a new EKS cluster

---

## Option A: Use Your Existing EKS Cluster

If you already have `migration-eks-cluster` from the cloud-migration-infra lab, you can use it directly:

```bash
aws eks update-kubeconfig --name migration-eks-cluster --region us-east-1
kubectl get nodes    # Verify connectivity
```

Skip to **Step 1** below.

## Option B: Create a New EKS Cluster with Terraform

Use the Terraform configuration in `terraform/` to create a standalone cluster:

```bash
cd terraform/
terraform init
terraform plan      # Review what will be created
terraform apply     # Type "yes" to confirm — takes ~15 minutes
```

Once the cluster is ready, configure kubectl:

```bash
# Terraform outputs this command for you
aws eks update-kubeconfig --name novamart-eks-cluster --region us-east-1
kubectl get nodes    # Verify connectivity
```

> **Note:** EKS clusters cost money while running. Remember to destroy the cluster when you're done (see Cleanup section).

---

## Step 1: Build the Docker Image

Review the Dockerfile in `docker/Dockerfile`. It uses a multi-stage build for a small, secure image.

```bash
# Build the image (run from the project root, where server.js is)
docker build -f phase3-rearchitect/docker/Dockerfile -t novamart-inventory:latest .

# Test locally
docker run -p 3000:3000 novamart-inventory:latest

# In another terminal, verify it works
curl http://localhost:3000/health
curl http://localhost:3000/api/products
```

**What to look for:**
- The image should be under 200 MB (check with `docker images`)
- The health check should return `{"status":"healthy"}`
- The container runs as user `novamart` (UID 1000), not root

---

## Step 2: Push to DockerHub

```bash
# Log in to DockerHub
docker login

# Tag the image with your DockerHub username
docker tag novamart-inventory:latest <your-dockerhub-username>/novamart-inventory:latest

# Push to DockerHub
docker push <your-dockerhub-username>/novamart-inventory:latest
```

---

## Step 3: Update Kubernetes Manifests

Before deploying, update these files with your values:

1. **`kubernetes/deployment.yaml`** -- Replace `<your-dockerhub-username>` with your actual DockerHub username
2. **`kubernetes/configmap.yaml`** -- Replace `<your-rds-endpoint>` with your RDS endpoint from Phase 2 (or leave as-is to use SQLite fallback)
3. **`kubernetes/secret.yaml`** -- Change `DB_PASSWORD` to your actual database password

---

## Step 4: Deploy to EKS

Apply the manifests in order (namespace first, then the resources that live in it):

```bash
# Apply all manifests at once — kubectl handles ordering by resource type
kubectl apply -f kubernetes/

# Or apply them one at a time for learning purposes:
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/secret.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/hpa.yaml
```

---

## Step 5: Verify the Deployment

```bash
# Check pods are running (should see 3 pods in "Running" state)
kubectl get pods -n novamart-ns

# Check the service (note the EXTERNAL-IP — it takes 2-3 minutes to provision)
kubectl get svc -n novamart-ns

# Check the HPA
kubectl get hpa -n novamart-ns

# Once the LoadBalancer has an EXTERNAL-IP, test the app
export LB_URL=$(kubectl get svc novamart-service -n novamart-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$LB_URL/health
curl http://$LB_URL/api/products
```

**Troubleshooting:**
```bash
# If pods aren't starting, check events
kubectl describe pod -n novamart-ns -l app=novamart

# Check container logs
kubectl logs -n novamart-ns -l app=novamart --tail=50

# If image pull fails, verify you pushed to DockerHub and updated deployment.yaml
```

---

## Step 6: Test Auto-Scaling

The HPA scales pods based on CPU utilization. Let's generate some load and watch it work.

```bash
# Terminal 1: Watch the HPA in real time
kubectl get hpa -n novamart-ns --watch

# Terminal 2: Generate load
export LB_URL=$(kubectl get svc novamart-service -n novamart-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in $(seq 1 1000); do
  curl -s http://$LB_URL/api/products > /dev/null &
done

# Wait 1-2 minutes and observe:
# - CPU utilization climbing above 70%
# - REPLICAS increasing (up to 10)
# - New pods appearing with kubectl get pods -n novamart-ns
```

After the load stops, watch the HPA scale back down (this takes ~5 minutes due to the scaleDown stabilization window).

---

## Step 7: Test Self-Healing

Kubernetes automatically restarts failed pods. Let's prove it:

```bash
# List current pods
kubectl get pods -n novamart-ns

# Delete one pod (simulating a crash)
kubectl delete pod <pod-name> -n novamart-ns

# Watch Kubernetes immediately create a replacement
kubectl get pods -n novamart-ns --watch
```

You should see the deleted pod enter `Terminating` state and a new pod appear within seconds. The Deployment controller ensures the desired replica count (3) is always maintained.

---

## Understanding the Kubernetes Manifests

### Namespace (`namespace.yaml`)
Namespaces provide isolation between applications in the same cluster. All NovaMart resources live in `novamart-ns` so they don't conflict with other apps.

### ConfigMap (`configmap.yaml`)
Stores non-sensitive configuration (environment, port, database host). ConfigMaps decouple configuration from the container image -- you can change config without rebuilding.

### Secret (`secret.yaml`)
Stores sensitive data (database credentials). Secrets are base64-encoded (not encrypted!) by default. In production, use AWS Secrets Manager with the External Secrets Operator for real encryption.

### Deployment (`deployment.yaml`)
Defines the desired state for your application:
- **replicas: 3** -- run three copies for high availability
- **resources** -- CPU/memory requests (guaranteed) and limits (maximum)
- **readinessProbe** -- tells the Service when a pod is ready to receive traffic
- **livenessProbe** -- tells Kubernetes when to restart a pod that's stuck
- **securityContext** -- runs as non-root, drops all Linux capabilities, read-only filesystem

### Service (`service.yaml`)
Exposes the pods to the internet via an AWS Network Load Balancer. The Service load-balances traffic across all healthy pods. Internal services would use `type: ClusterIP` instead.

### HPA (`hpa.yaml`)
Watches CPU utilization and adjusts the number of pods:
- Scales up quickly (2 pods every 60 seconds) to handle traffic spikes
- Scales down slowly (1 pod every 120 seconds, with a 5-minute stabilization window) to avoid flapping

---

## The Full Migration Journey

```
Phase 1: Rehost              Phase 2: Replatform           Phase 3: Re-Architect
(Lift & Shift)                (Lift & Reshape)              (Containerize)

  On-Premises                   AWS (EC2 + RDS)               AWS (EKS)
  +-----------+                 +-----------+                 +-------------+
  | Server    |   -------->     | EC2 + ALB |   -------->     | EKS Cluster |
  | (Node.js) |   "Move it"    | + RDS     |   "Rebuild it"  | + HPA       |
  | + SQLite  |                 | + ASG     |                 | + Probes    |
  +-----------+                 +-----------+                 +-------------+

  Manual scaling                Auto Scaling Group            Horizontal Pod
  Single point of failure       Multi-AZ, managed DB          Autoscaler
  Config in files               Config in user data           ConfigMaps + Secrets
  No health checks              ALB health checks             Liveness + Readiness
```

Each phase builds on the last. You don't have to jump straight to EKS -- many production workloads run perfectly well on EC2 with RDS. Choose the migration strategy that matches your team's skills and business needs.

---

## Cleanup

When you're done, clean up to avoid ongoing charges:

```bash
# Remove all Kubernetes resources
kubectl delete namespace novamart-ns

# If you created the EKS cluster with Terraform (Option B)
cd terraform/
terraform destroy    # Type "yes" to confirm — takes ~15 minutes

# Remove the local Docker image
docker rmi novamart-inventory:latest
docker rmi <your-dockerhub-username>/novamart-inventory:latest
```

---

## What's Next?

Now that you've completed all three migration phases, explore these advanced topics:

- **CI/CD Pipeline** -- Automatically build and deploy on git push (see `healthcare-cicd-lab`)
- **GitOps with ArgoCD** -- Declarative deployments synced from Git (see `gitops-argocd-lab`)
- **Container Security** -- Scan images for vulnerabilities before deploying (see `container-security-lab`)
- **Logging and Observability** -- Centralized logging with CloudWatch or EFK stack (see `logging-observability-lab`)
