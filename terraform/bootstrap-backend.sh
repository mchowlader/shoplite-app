#!/usr/bin/env bash
# ==============================================================================
# ShopLite: One-Command Terraform S3 + DynamoDB Remote State Bootstrap (Q4.e)
# Creates an S3 state bucket, DynamoDB lock table, and generates backend.hcl.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
BUCKET_NAME="${TF_STATE_BUCKET:-shoplite-tfstate-${ACCOUNT_ID}-${AWS_REGION}}"
LOCK_TABLE="${TF_LOCK_TABLE:-shoplite-terraform-locks}"

echo "[INFO] Bootstrapping Terraform remote state in ${AWS_REGION} (Account: ${ACCOUNT_ID})..."

if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}"
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    echo "[OK] Created encrypted, versioned S3 bucket: ${BUCKET_NAME}"
else
    echo "[INFO] S3 bucket ${BUCKET_NAME} already exists."
fi

if ! aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" &>/dev/null; then
    aws dynamodb create-table \
        --table-name "${LOCK_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${AWS_REGION}" >/dev/null
    aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${AWS_REGION}"
    echo "[OK] Created DynamoDB lock table: ${LOCK_TABLE}"
else
    echo "[INFO] DynamoDB lock table ${LOCK_TABLE} already exists."
fi

cat > backend.hcl <<EOF
bucket         = "${BUCKET_NAME}"
key            = "shoplite/dev/terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${LOCK_TABLE}"
encrypt        = true
EOF

echo "[SUCCESS] Wrote terraform/backend.hcl. Next run:"
echo "  terraform init -backend-config=backend.hcl -reconfigure"
