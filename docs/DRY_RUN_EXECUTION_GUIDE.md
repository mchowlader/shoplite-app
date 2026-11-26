# ShopLite DevOps Capstone (`DEVOPS-CAP-601`): Complete Personal AWS & WSL2 Dry-Run Guide

**Single Authoritative Execution Guide** — Covers local Docker validation (Q1–Q2), Personal AWS non-root IAM setup, Pure SSM infrastructure via Terraform + Ansible (Q3–Q4), automated CI/CD to ECR + ArgoCD GitOps (Q5 & Q7), LGTM Observability + Grafana `/grafana/` verification (Q6), Chaos RCA (Q8), Cost Budget, and Zero-Bill automated teardown.

---

## 1. Estimated AWS Cost Budget & Zero-Bill Policy (`ap-southeast-1`)

The core Kubernetes nodes (`t3.medium`), NAT Gateway, and ALB are billed hourly and are **not** included in the AWS 12-month Free Tier (unless covered by promotional credits on a newly registered AWS account).

| Resource | Specification | Rate (`ap-southeast-1`) | 4-Hour Dry Run Estimate | Post-Teardown Ongoing Cost |
|---|---|---|---|---|
| **3x EC2 Instances** | `t3.medium` (1 Control Plane + 2 Workers, 6 vCPU total) | `~$0.046/hr` each (`~$0.14/hr` total) | `~$0.56` | `$0.00` |
| **1x NAT Gateway** | Single-AZ NAT + data transfer | `$0.045/hr` + `$0.045/GB` | `~$0.18 + ~$0.15 data` | `$0.00` |
| **1x Application Load Balancer** | Public HTTP/80 ALB | `~$0.025/hr` | `~$0.10` | `$0.00` |
| **EBS `gp3` Storage** | 3x 30 GB root + 2x 10 GB worker data (110 GB total) | `~$0.096/GB-month` | `< $0.02` | `$0.00` |
| **ECR + S3 State/SSM + DynamoDB** | 3 ECR repos, tiny tfstate, on-demand lock table | Pay-per-use / Free Tier | `< $0.02` | `$0.00` |
| **Total Estimate** | **Full End-to-End Dry Run (3–4 Hours)** | **`~$0.21/hr`** | **`~$0.85 – $1.25 USD`** | **`$0.00 / month`** |

- **Budget Guard:** Terraform automatically provisions `aws_budgets_budget.cost_guard` (`limit_amount = "20"` USD, customizable in `terraform/terraform.tfvars` via `alert_email`).
- **Quota Pre-Check:** Verify in AWS Console → **Service Quotas → Amazon EC2 → Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances** that `ap-southeast-1` allows at least **6 vCPUs**.

---

## 2. Personal AWS Non-Root IAM User & GitHub Secrets Setup

Never generate Access Keys on the AWS Root User (`root`), and never run day-to-day CLI operations as Linux `root` (`sudo -i`). Use a dedicated non-root IAM user just like enterprise/Poridhi workflows.

### 2.1 Create IAM User & Access Key
1. Open **AWS Console → IAM → Users → Create user** (e.g., `shoplite-devops`, **do not** enable console root privileges beyond testing).
2. Under **Permissions options → Attach policies directly**, attach `AdministratorAccess` (for full capstone testing across VPC, EC2, ELB, ECR, IAM, S3, DynamoDB, SSM, and Budgets), then create the user.
3. Open `shoplite-devops` → **Security credentials → Create access key → Command Line Interface (CLI)** → confirm and save:
   - `AWS_ACCESS_KEY_ID` (`AKIA...`)
   - `AWS_SECRET_ACCESS_KEY`

### 2.2 Configure GitHub Repository Secrets (`shoplite-app`)
Open `https://github.com/mchowlader/shoplite-app/settings/secrets/actions`:
- `AWS_ACCESS_KEY_ID`: `<AKIA...>`
- `AWS_SECRET_ACCESS_KEY`: `<secret>`
- `GITOPS_PAT`: GitHub Personal Access Token with `Contents: Read and Write` scope on `mchowlader/shoplite-gitops`.
- **`AWS_SESSION_TOKEN`:** Delete or leave unset if present (personal IAM user keys do not use temporary STS session tokens; only Poridhi sandbox `ASIA...` keys use it).
- *(Optional Exam Rubric OIDC)*: If you create a GitHub OIDC IAM Role in personal AWS later, set `AWS_ROLE_ARN` instead of static access keys.

> **Security Standard After Dry Run:** Once testing finishes and `cleanup-backend.sh` reports zero resources, go to **IAM → Users → `shoplite-devops` → Security credentials** and **Deactivate/Delete** the `AKIA...` access key (or delete the temporary test user).

---

## 3. WSL2 Prerequisites & Pure SSM Verification

All CLI tools must run as your normal WSL2 user (`mithun`), never inside `sudo -i`.

### 3.1 Verified Baseline vs Pure SSM Additions
On WSL2 (`Ubuntu 26.04 LTS`, `x86_64`), ensure `session-manager-plugin` and `python3-boto3` are installed so Ansible `amazon.aws.aws_ssm` and `aws ssm start-session` work with **zero SSH keys or open Port 22**:

```bash
# Install AWS Session Manager Plugin & boto3 for Pure SSM mode (Ubuntu x86_64)
curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/ssm-plugin.deb && \
sudo dpkg -i /tmp/ssm-plugin.deb && \
rm -f /tmp/ssm-plugin.deb && \
sudo apt-get update && sudo apt-get install -y python3-boto3
```

### 3.2 Configure Personal AWS CLI in WSL2
```bash
aws configure
# AWS Access Key ID: <AKIA...>
# AWS Secret Access Key: <secret>
# Default region name: ap-southeast-1
# Default output format: json

aws sts get-caller-identity
session-manager-plugin --version
```

---

## 4. Assessment Repository Structure (Section 2.1 Compliance, Zero Duplicates)

Both repositories follow the exact `DEVOPS-CAP-601` structure without duplicate manifests or conflicting configs:

- **`shoplite-app/`**
  - `services/{web,catalog-api,order-worker}/`: App source, multi-stage non-root Dockerfiles (`<150 MB`), JSON logging with active OTel `trace_id`, fault-injection flags, Prometheus metrics.
  - `docker-compose.yml`, `Makefile`, `scripts/smoke-test.sh`: Q1–Q2 local stack (`make up && make smoke`).
  - `linux/{sshd_config,systemd/,firewall/,evidence/}`: Q3 canonical hardening configs (referenced directly by Ansible — zero copies).
  - `terraform/modules/{network,compute,alb,ecr}/` + `bootstrap-backend.sh` + `cleanup-backend.sh`: Q4 IaC with Pure SSM (`enable_ssh_bastion=false`) and Bastion fallback (`enable_ssh_bastion=true`).
  - `ansible/{ansible.cfg,site.yml,playbook.yml,cluster-init.yml,run-ansible.sh,roles/}`: Q3 + Q4.g automation.
  - `helm/shoplite/`: Q5 single Helm chart (Probes, HPA, PDB, NetworkPolicy, non-root, Ingress, optional Canary Rollout).
  - `monitoring/{alert-rules,dashboards,grafana,loki,prometheus,runbooks,tempo,deploy-observability.sh}`: Q6 LGTM stack & alerts.
  - `.github/workflows/app-ci.yml`: Q7 PR validation + main CI/CD (Hadolint, Pytest, Helm lint, Trivy CRITICAL fail, ECR push, `shoplite-gitops` SHA bump).
  - `scripts/deploy-platform.sh`, `scripts/load-test.py`, `docs/`: Platform bootstrap, Q8 load generator, architecture SVG, and RCA template.
- **`shoplite-gitops/`**
  - `apps/argocd-applications/{shoplite-dev.yaml,shoplite-prod.yaml}`: Dev (auto-sync + self-heal) and Prod (manual sync + self-heal).
  - `envs/{dev,prod}/values.yaml`: Environment overrides updated by CI without ever running `kubectl apply` inside GitHub Actions.

---

## 5. End-to-End Automated Dry-Run Execution (Pure SSM Default)

### Step 1: Local Q1–Q2 Verification (Zero AWS Cost)
```bash
cd "/mnt/d/MCH/DevOps/DevOpsPractices/Final Capstone Assessment/shoplite-app"
make up && make smoke
make down
```
*(Expected: `ALL SMOKE TESTS PASSED`, matching `trace_id` across `catalog-api` and `order-worker`, containers removed cleanly.)*

### Step 2: Push Uncommitted Changes & Run CI/CD Pipeline (Q7 Automation)
Ensure your local changes in both `shoplite-app` and `shoplite-gitops` are committed and pushed to GitHub (`main`).
- Pushing to `shoplite-app` `main` (or clicking **Actions → ShopLite CI/CD Pipeline → Run workflow**) builds `web`, `catalog-api`, and `order-worker`, runs `pytest` + `hadolint` + `trivy` (`CRITICAL`), pushes to your personal AWS ECR, and commits the new ECR repository URLs + short SHA tag into `shoplite-gitops/envs/dev/values.yaml` (and ECR repository URLs into `envs/prod/values.yaml`).
- **Wait until the GitHub Actions workflow completes green before Step 4.**

> **Note:** On a brand-new personal AWS account, run Step 3 (`terraform apply`) **before** manually running Step 2's workflow, so the 3 ECR repositories already exist when GitHub Actions pushes images!

### Step 3: Provision AWS Infrastructure (Terraform — Pure SSM Mode)
```bash
cd "/mnt/d/MCH/DevOps/DevOpsPractices/Final Capstone Assessment/shoplite-app/terraform"
cp -n terraform.tfvars.example terraform.tfvars   # Optional: set alert_email

./bootstrap-backend.sh
terraform init -backend-config=backend.hcl -reconfigure
terraform apply -auto-approve
```
**What happens automatically (Pure SSM default `enable_ssh_bastion=false`):**
- Control plane and both workers boot inside **private subnets** with **zero public IPs** and **no Port 22 open**.
- Terraform provisions the ALB, 3 ECR repositories, two 10 GB `gp3` worker EBS volumes, an ephemeral S3 SSM staging bucket (`force_destroy = true`), and generates `../ansible/inventory/hosts.ini` configured for `amazon.aws.aws_ssm`.

*(Sandbox fallback only: if an environment blocks SSM endpoints, create `shoplite-key.pem` and run `terraform apply -var="enable_ssh_bastion=true" -auto-approve`.)*

### Step 4: Bootstrap OS, Q3 Hardening, Kubernetes, Ingress & ArgoCD (One Command over SSM)
```bash
cd "/mnt/d/MCH/DevOps/DevOpsPractices/Final Capstone Assessment/shoplite-app/ansible"
./run-ansible.sh all
```
- `run-ansible.sh` automatically waits until all 3 EC2 nodes register `Online` in AWS SSM, then runs `site.yml` (`playbook.yml` + `cluster-init.yml`) over AWS SSM—zero manual SSH required.
- Automatically configures `deploy`/`ops`, `setfacl`, `sshd`, UFW, `shoplite-backup.timer`, `containerd`, `kubelet` ECR credential provider, `kubeadm`, Calico CNI, 10 GB EBS mounts (`/var/lib/shoplite-storage`), `ingress-nginx` DaemonSet, `local-path` StorageClass, `shoplite-db-secret` (out-of-band), ArgoCD, Argo Rollouts, and writes `/opt/shoplite/alb-dns.txt`.

### Step 5: Deploy ShopLite GitOps Apps & LGTM Observability via SSM (One Command)
Connect directly to the private Control Plane node using AWS SSM Session Manager from WSL2:
```bash
CP_ID="$(terraform -chdir=../terraform output -raw control_plane_id)"
aws ssm start-session --target "${CP_ID}" --region ap-southeast-1
```
Inside the SSM session, switch to `ubuntu`, clone both repos, and run the single platform script:
```bash
sudo -iu ubuntu
git clone https://github.com/mchowlader/shoplite-app.git ~/shoplite-app
git clone https://github.com/mchowlader/shoplite-gitops.git ~/shoplite-gitops
~/shoplite-app/scripts/deploy-platform.sh
```
This registers `shoplite-dev` (auto-sync) and `shoplite-prod` (manual-sync) in ArgoCD, auto-reads `/opt/shoplite/alb-dns.txt` so Grafana binds to the exact ALB domain, deploys Prometheus + Alertmanager + Loki + Promtail + Tempo + Grafana into `monitoring`, and prints all live URLs and the ArgoCD admin password.

---

## 6. Grafana URL, Login Troubleshooting & Assessment Checkpoints

### 6.1 Grafana Access & Why Login Loops Happen Behind ALB
- **Live Grafana URL:** `http://<ALB-DNS>/grafana/` (include the trailing `/`, login: `admin` / `admin`).
- **Poridhi Requirement:** Question 6 deploys Grafana inside the `monitoring` namespace so reviewers can correlate Metrics → Logs (`trace_id`) → Tempo Traces in `< 2 minutes`. It does not restrict you to a single URL path; exposing `/grafana/` via `ingress-nginx` behind the ALB is the standard seamless entry point.
- **Why Grafana Previously Stuck After Login (Fixed):**
  1. `kube-prometheus-stack-values.yaml` used `root_url: "%(protocol)s://%(domain)s/grafana/"` without overriding default `domain=localhost` or HTTP cookie flags, causing Grafana 11 login redirects/CSRF cookies to fail on `http://<ALB-DNS>/grafana/`.
  2. **Applied Fix:** `kube-prometheus-stack-values.yaml` now sets `enforce_domain: false`, `cookie_secure: false`, `cookie_samesite: lax`, `allow_embedding: true`, `grafana-ingress.yaml` increases `proxy-buffer-size: "16k"`, and `deploy-observability.sh` automatically injects `server.domain=<ALB-DNS>` from `/opt/shoplite/alb-dns.txt`.
  3. Always open `http://<ALB-DNS>/grafana/` in a clean/incognito tab so stale `/` or `localhost` session cookies don't conflict.
  4. **Direct SSM Port-Forward Fallback (zero ingress dependency):** From WSL2, run `kubectl` port-forward via SSM (`AWS-StartPortForwardingSessionToRemoteHost` or inside SSM session) if ever needed for debugging.

### 6.2 Live Verification Checklist (Q5, Q6, Q7, Q8)
1. **Q5 Browser Order Flow:** Open `http://<ALB-DNS>/` → place an order → confirm status transitions `PENDING` → `PROCESSING` → `COMPLETED`.
2. **Q6 LGTM Correlation in Grafana (`http://<ALB-DNS>/grafana/`):**
   - Open **Dashboards → ShopLite - Golden Signals** (confirm p50/p95/p99 latency, RPS, 5xx rate, pod CPU/RAM, queue depth, worker replicas, created vs processed orders).
   - Click an **Exemplar** on latency → jumps directly to **Tempo** waterfall trace (`catalog-api -> redis -> order-worker -> postgres`) → click **Logs for this span** to view matching **Loki** JSON logs by `trace_id`.
3. **Q7 CI/CD Push-to-Browser & Self-Heal:**
   - Change the title in `services/web/index.html`, push to `shoplite-app` `main`, wait for CI to bump `shoplite-gitops/envs/dev/values.yaml`, then refresh `http://<ALB-DNS>/` (auto-synced by ArgoCD without running `kubectl apply`).
   - Run `kubectl scale deployment -n shoplite-dev shoplite-frontend --replicas=3` and watch ArgoCD revert it back to `1`.
4. **Q8 Chaos & RCA (`prod` namespace `shoplite`):**
   - Delete or disable `shoplite-dev` Ingress (`kubectl delete application shoplite-dev -n argocd`), sync `shoplite-prod` from ArgoCD UI/CLI so `shoplite` namespace serves `http://<ALB-DNS>/`.
   - Enable one chaos flag in `shoplite-gitops/envs/prod/values.yaml` (`latencyMs: "2000"`, `errorRate: "0.2"`, `memoryLeak: "true"`, or `slowDb: "true"`), run load (`python3 ~/shoplite-app/scripts/load-test.py --url http://<ALB-DNS> --rps 25 --duration 900`), trace exclusively in Grafana → Loki → Tempo, revert commit, and update `docs/RCA-INCIDENT-REPORT.md`.

---

## 7. Zero-Bill Automated Teardown (Must Run Immediately After Testing)

Exit the Control Plane SSM session (`exit` twice back to WSL2 `mithun@PTSL-Mithun`), then execute both teardown commands:

```bash
cd "/mnt/d/MCH/DevOps/DevOpsPractices/Final Capstone Assessment/shoplite-app/terraform"

# 1. Destroy VPC, EC2, EBS volumes, ALB, NAT Gateway, EIP, ECR repos, SSM S3 bucket & Budget
terraform destroy -auto-approve

# 2. Delete S3 remote state bucket (all versions), DynamoDB lock table, optional SSH key & verify 0 resources
./cleanup-backend.sh --delete-key --yes
```

Confirm the script finishes with:
`[SUCCESS] Zero active/billable ShopLite resources remain in ap-southeast-1.`

### Final AWS Console Check (Takes 60 Seconds)
1. **IAM → Users → `shoplite-devops` → Security credentials:** Delete or deactivate your `AKIA...` test access key.
2. **AWS Billing Dashboard → Bills** (next day): Confirm no active EIP, NAT Gateway, EBS volume, EC2 instance, or ALB charges are accruing.
