# 🔄 SSM Reversion & SSH Rollback Checklist

**Context:**  
Due to an AWS Organizations Service Control Policy (SCP) restriction (`AllowedByOrganizations: False`) on `ssmmessages:CreateControlChannel` and `ec2messages:GetMessages` in Poridhi lab account `779846822536`, temporary SSH access via a public Control-Plane bastion was enabled in commit `2787d74` to complete live dry runs without waiting.

Once Poridhi Support updates the SCP or authorizes full SSM access, follow this deterministic 3-step rollback procedure to restore 100% private-subnet architecture with SSM Session Manager access.

---

## 📌 Commit Reference
* **Pure SSM Baseline (Private Subnets, No Port 22):** Commit `d75a988`
* **Temporary SSH Bastion (Dry-Run Bypass):** Commit `2787d74`

---

## 🛠️ Step-by-Step Reversion Procedure

### Step 1: Revert Terraform Configuration to Pure SSM
In `shoplite-app` repo root:
```bash
cd ~/code/shoplite-app
git revert 2787d74 --no-edit
git push origin main
```
*What this restores:*
1. Removes Port 22 SSH ingress rule from `modules/network/main.tf` (`shoplite-nodes-sg`).
2. Moves Control Plane back into `private_subnet_ids[0]` (removes public IP).
3. Resets `key_name` to default `""` in `modules/compute/main.tf`.
4. Removes `control_plane_public_ip` output.

---

### Step 2: Apply Clean Private Infrastructure
```bash
cd ~/code/shoplite-app/terraform
terraform apply -auto-approve
```
*Verification:*
* Control Plane IP will be strictly private (`10.0.10.x`).
* Port 22 inbound will be closed.

---

### Step 3: Delete Temporary AWS EC2 Key Pair
```bash
aws ec2 delete-key-pair --key-name "shoplite-key" --region ap-southeast-1
```
