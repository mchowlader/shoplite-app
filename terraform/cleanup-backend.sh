#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Post-Destroy Backend Cleanup & Zero-Bill Verification Script
# Run this AFTER `terraform destroy` completes cleanly.
# Deletes:
#   1. All object versions/delete-markers and S3 bucket created by bootstrap-backend.sh
#   2. DynamoDB lock table created by bootstrap-backend.sh
#   3. Optional EC2 SSH KeyPair (--delete-key)
#   4. Local generated artifacts (backend.hcl, backend_override.tf, plan.txt)
# Finally runs a zero-bill verification scan across the target AWS region.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

AWS_REGION="${TF_VAR_aws_region:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}}"
LOCK_TABLE="${TF_LOCK_TABLE:-shoplite-terraform-locks}"
KEY_NAME="${TF_KEY_NAME:-shoplite-key}"
DELETE_KEY=false
AUTO_YES=false
VERIFY_ONLY=false

for arg in "$@"; do
  case "${arg}" in
    --delete-key)
      DELETE_KEY=true
      ;;
    --yes|-y)
      AUTO_YES=true
      ;;
    --verify-only)
      VERIFY_ONLY=true
      ;;
    --help|-h)
      echo "Usage: $0 [--delete-key] [--yes|-y] [--verify-only]"
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: ${arg}" >&2
      exit 1
      ;;
  esac
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET_NAME="${TF_STATE_BUCKET:-shoplite-tfstate-${ACCOUNT_ID}-${AWS_REGION}}"

echo "[INFO] AWS Account : ${ACCOUNT_ID}"
echo "[INFO] AWS Region  : ${AWS_REGION}"
echo "[INFO] State Bucket: ${BUCKET_NAME}"
echo "[INFO] Lock Table  : ${LOCK_TABLE}"

verify_zero_bill() {
  local issues=0
  echo ""
  echo "================ AWS ZERO-BILL VERIFICATION (${AWS_REGION}) ================"

  local running_ec2
  running_ec2="$(aws ec2 describe-instances --region "${AWS_REGION}" \
    --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]' \
    --output text)"
  if [ -n "${running_ec2}" ]; then
    echo "[WARN] Non-terminated EC2 instances found:"
    echo "${running_ec2}"
    issues=$((issues + 1))
  else
    echo "[OK] EC2 instances         : 0 active/stopped"
  fi

  local nat_gws
  nat_gws="$(aws ec2 describe-nat-gateways --region "${AWS_REGION}" \
    --filter "Name=state,Values=pending,available,deleting" \
    --query 'NatGateways[].[NatGatewayId,State]' --output text)"
  if [ -n "${nat_gws}" ]; then
    echo "[WARN] NAT Gateways found (hourly billed):"
    echo "${nat_gws}"
    issues=$((issues + 1))
  else
    echo "[OK] NAT Gateways          : 0"
  fi

  local eips
  eips="$(aws ec2 describe-addresses --region "${AWS_REGION}" \
    --query 'Addresses[].[PublicIp,AllocationId,AssociationId]' --output text)"
  if [ -n "${eips}" ]; then
    echo "[WARN] Elastic IPs found (idle EIPs incur hourly fees):"
    echo "${eips}"
    issues=$((issues + 1))
  else
    echo "[OK] Elastic IPs           : 0"
  fi

  local albs
  albs="$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" \
    --query 'LoadBalancers[?starts_with(LoadBalancerName, `shoplite`)].[LoadBalancerName,State.Code]' \
    --output text)"
  if [ -n "${albs}" ]; then
    echo "[WARN] ShopLite Load Balancers found (hourly billed):"
    echo "${albs}"
    issues=$((issues + 1))
  else
    echo "[OK] ShopLite ALBs         : 0"
  fi

  local volumes
  volumes="$(aws ec2 describe-volumes --region "${AWS_REGION}" \
    --query 'Volumes[].[VolumeId,Size,VolumeType,State]' --output text)"
  if [ -n "${volumes}" ]; then
    echo "[WARN] EBS Volumes found (billed per GB-month):"
    echo "${volumes}"
    issues=$((issues + 1))
  else
    echo "[OK] EBS Volumes           : 0"
  fi

  local ecr_repos
  ecr_repos="$(aws ecr describe-repositories --region "${AWS_REGION}" \
    --query 'repositories[?starts_with(repositoryName, `shoplite/`)].repositoryName' \
    --output text 2>/dev/null || true)"
  if [ -n "${ecr_repos}" ]; then
    echo "[WARN] ShopLite ECR repositories still exist: ${ecr_repos}"
    issues=$((issues + 1))
  else
    echo "[OK] ShopLite ECR repos    : 0"
  fi

  local ssm_buckets
  ssm_buckets="$(aws s3api list-buckets \
    --query 'Buckets[?starts_with(Name, `shoplite-ssm-staging-`)].Name' \
    --output text 2>/dev/null || true)"
  if [ -n "${ssm_buckets}" ]; then
    echo "[WARN] ShopLite SSM staging S3 bucket(s) still exist: ${ssm_buckets}"
    issues=$((issues + 1))
  else
    echo "[OK] SSM staging buckets   : 0"
  fi

  if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "[WARN] Terraform state S3 bucket still exists: ${BUCKET_NAME}"
    issues=$((issues + 1))
  else
    echo "[OK] State S3 bucket       : deleted"
  fi

  if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "[WARN] Terraform lock DynamoDB table still exists: ${LOCK_TABLE}"
    issues=$((issues + 1))
  else
    echo "[OK] Lock DynamoDB table   : deleted"
  fi

  echo "============================================================================"
  if [ "${issues}" -eq 0 ]; then
    echo "[SUCCESS] Zero active/billable ShopLite resources remain in ${AWS_REGION}."
    return 0
  else
    echo "[ALERT] ${issues} resource group(s) still exist! Clean them up before closing." >&2
    return 1
  fi
}

if [ "${VERIFY_ONLY}" = true ]; then
  verify_zero_bill
  exit $?
fi

# Safety guard: refuse deleting Terraform state backend while ShopLite EC2/NAT/ALB exist
shoplite_active_ec2="$(aws ec2 describe-instances --region "${AWS_REGION}" \
  --filters "Name=tag:project,Values=shoplite" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
shoplite_active_albs="$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" \
  --query 'LoadBalancers[?starts_with(LoadBalancerName, `shoplite`)].LoadBalancerName' --output text)"

if [ -n "${shoplite_active_ec2}" ] || [ -n "${shoplite_active_albs}" ]; then
  echo "[ERROR] Active ShopLite resources detected (EC2: '${shoplite_active_ec2}', ALB: '${shoplite_active_albs}')." >&2
  echo "Run 'terraform destroy -auto-approve' BEFORE deleting backend state!" >&2
  exit 1
fi

if [ "${AUTO_YES}" = false ]; then
  read -r -p "Delete S3 bucket '${BUCKET_NAME}' and DynamoDB table '${LOCK_TABLE}'? [y/N] " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "[INFO] Aborted backend deletion."
    exit 0
  fi
fi

# 1. Empty all object versions & delete-markers, then delete S3 bucket
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "[INFO] Emptying versioned S3 bucket '${BUCKET_NAME}'..."
  python3 - "${BUCKET_NAME}" "${AWS_REGION}" <<'PYEOF'
import json
import subprocess
import sys

bucket, region = sys.argv[1], sys.argv[2]
deleted_total = 0
key_marker = None
version_id_marker = None

while True:
    cmd = ["aws", "s3api", "list-object-versions", "--bucket", bucket, "--region", region, "--output", "json"]
    if key_marker:
        cmd.extend(["--key-marker", key_marker])
    if version_id_marker:
        cmd.extend(["--version-id-marker", version_id_marker])

    raw = subprocess.check_output(cmd, text=True)
    data = json.loads(raw) if raw.strip() else {}
    objects = []
    for item in data.get("Versions", []):
        objects.append({"Key": item["Key"], "VersionId": item["VersionId"]})
    for item in data.get("DeleteMarkers", []):
        objects.append({"Key": item["Key"], "VersionId": item["VersionId"]})

    for i in range(0, len(objects), 1000):
        batch = {"Objects": objects[i:i + 1000], "Quiet": True}
        subprocess.run(
            [
                "aws", "s3api", "delete-objects",
                "--bucket", bucket,
                "--region", region,
                "--delete", json.dumps(batch),
            ],
            check=True,
        )
        deleted_total += len(batch["Objects"])

    if not data.get("IsTruncated"):
        break
    key_marker = data.get("NextKeyMarker")
    version_id_marker = data.get("NextVersionIdMarker")

print(f"[INFO] Deleted {deleted_total} object version(s)/marker(s).")
PYEOF
  aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
  echo "[OK] Deleted S3 bucket '${BUCKET_NAME}'."
else
  echo "[INFO] S3 bucket '${BUCKET_NAME}' already absent."
fi

# 2. Delete DynamoDB lock table
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "[INFO] Deleting DynamoDB table '${LOCK_TABLE}'..."
  aws dynamodb delete-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" >/dev/null
  aws dynamodb wait table-not-exists --table-name "${LOCK_TABLE}" --region "${AWS_REGION}"
  echo "[OK] Deleted DynamoDB table '${LOCK_TABLE}'."
else
  echo "[INFO] DynamoDB table '${LOCK_TABLE}' already absent."
fi

# 3. Optional EC2 key pair cleanup
if [ "${DELETE_KEY}" = true ]; then
  if aws ec2 describe-key-pairs --key-names "${KEY_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws ec2 delete-key-pair --key-name "${KEY_NAME}" --region "${AWS_REGION}"
    echo "[OK] Deleted EC2 KeyPair '${KEY_NAME}' in ${AWS_REGION}."
  else
    echo "[INFO] EC2 KeyPair '${KEY_NAME}' already absent."
  fi
fi

# 4. Clean local generated files
rm -f "${SCRIPT_DIR}/backend.hcl" "${SCRIPT_DIR}/backend_override.tf" "${SCRIPT_DIR}/plan.txt"
echo "[INFO] Removed local backend.hcl / backend_override.tf / plan.txt."

verify_zero_bill
