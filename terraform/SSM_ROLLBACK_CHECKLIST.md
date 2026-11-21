# 🔄 SSM & SSH Architecture Toggle Guide

**Context:**  
Due to AWS Organizations Service Control Policy (SCP) restrictions (`AllowedByOrganizations: False`) on `ssmmessages:CreateControlChannel` and `ec2messages:GetMessages` in Poridhi lab sandbox account `779846822536`, a deterministic Terraform Feature Toggle (`enable_ssh_bastion`) has been introduced directly on the `main` branch.

This eliminates divergent Git branches and prevents any code drift or merge conflicts between dry runs and final exam evaluation.

---

## 📌 Architecture Modes on `main` Branch

### 1. Default Mode: Pure SSM Architecture (100% Exam-Compliant)
By default, `enable_ssh_bastion = false`:
* **Port 22 SSH Ingress:** Closed (not provisioned in `shoplite-nodes-sg`).
* **Control-Plane Subnet:** 100% Private (`10.0.10.x`).
* **Associate Public IP:** `false` (no public IP assigned).
* **Worker Subnets:** 100% Private (`10.0.10.x`, `10.0.20.x`).
* **Instance Profile:** `AmazonSSMManagedInstanceCore` attached to all nodes.
* **Evaluation Standard:** Strictly adheres to Zero-Trust architecture and Principle of Least Privilege.

Command:
```bash
terraform apply -auto-approve
```

---

### 2. Poridhi Lab Mode: SSH Bastion Fallback (Dry-Run Mode)
When running inside Poridhi sandbox where SSM is restricted:
* **Control-Plane Subnet:** Placed in Public Subnet (`10.0.1.x`) acting as Bastion host.
* **Associate Public IP:** `true`.
* **Port 22 SSH Ingress:** Dynamically opened on `shoplite-nodes-sg`.
* **Worker Nodes:** Remain 100% Private in private subnets.

Command:
```bash
terraform apply -var="enable_ssh_bastion=true" -auto-approve
```

---

## 🛠️ Post-Lab Key Cleanup
If `enable_ssh_bastion=true` was used with an EC2 key-pair, cleanup via:
```bash
aws ec2 delete-key-pair --key-name "shoplite-key" --region ap-southeast-1
```
