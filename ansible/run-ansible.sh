#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Automated Ansible Execution Harness (Question 4.g)
# Usage: ./run-ansible.sh [check|bootstrap|cluster|all]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
export ANSIBLE_CONFIG="${SCRIPT_DIR}/ansible.cfg"

MODE="${1:-all}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}  ShopLite Ansible Automation Suite — Mode: ${MODE}                ${NC}"
echo -e "${BLUE}===================================================================${NC}"

if [ ! -f inventory/hosts.ini ]; then
    echo -e "${RED}[ERROR] inventory/hosts.ini not found! Run 'terraform apply' first so Terraform generates it.${NC}"
    exit 1
fi

if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${YELLOW}[INFO] ansible-playbook not found. Installing Ansible automatically...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y ansible
fi

# Pure SSM mode prerequisites (session-manager-plugin, boto3, and Online SSM registration wait)
if grep -q "ansible_connection=amazon.aws.aws_ssm" inventory/hosts.ini; then
    if ! command -v session-manager-plugin &>/dev/null; then
        echo -e "${RED}[ERROR] AWS session-manager-plugin not found (required for Pure SSM mode).${NC}"
        echo "Install in WSL2 Ubuntu (x86_64):"
        echo "  curl -fsSL 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb' -o /tmp/ssm-plugin.deb && sudo dpkg -i /tmp/ssm-plugin.deb && rm -f /tmp/ssm-plugin.deb"
        exit 1
    fi
    if ! python3 -c "import boto3" 2>/dev/null; then
        echo -e "${YELLOW}[INFO] python3-boto3 not found (required for aws_ssm). Installing automatically...${NC}"
        sudo apt-get update -y
        sudo apt-get install -y python3-boto3
    fi

    SSM_REGION="$(grep -E '^aws_region=' inventory/hosts.ini | head -n1 | cut -d"'" -f2)"
    SSM_REGION="${SSM_REGION:-ap-southeast-1}"
    SSM_IDS=($(grep -Eo 'i-[0-9a-f]+' inventory/hosts.ini | sort -u))
    if [ "${#SSM_IDS[@]}" -gt 0 ]; then
        echo -e "${YELLOW}[INFO] Waiting up to 180s for EC2 instances (${SSM_IDS[*]}) to register Online in SSM (${SSM_REGION})...${NC}"
        for attempt in $(seq 1 36); do
            online_count="$(aws ssm describe-instance-information --region "${SSM_REGION}" \
              --filters "Key=InstanceIds,Values=$(IFS=,; echo "${SSM_IDS[*]}")" \
              --query "length(InstanceInformationList[?PingStatus=='Online'])" --output text 2>/dev/null || echo 0)"
            if [ "${online_count}" -ge "${#SSM_IDS[@]}" ]; then
                echo -e "${GREEN}[OK] All ${#SSM_IDS[@]} nodes registered Online in AWS SSM.${NC}"
                break
            fi
            if [ "${attempt}" -eq 36 ]; then
                echo -e "${RED}[ERROR] Timed out waiting for SSM Online status (got ${online_count}/${#SSM_IDS[@]}).${NC}" >&2
                exit 1
            fi
            sleep 5
        done
    fi
fi

case "${MODE}" in
    check)
        echo -e "${GREEN}[INFO] Verifying Playbook Syntaxes...${NC}"
        ansible-playbook -i inventory/hosts.ini playbook.yml --syntax-check
        ansible-playbook -i inventory/hosts.ini cluster-init.yml --syntax-check
        echo -e "${GREEN}[SUCCESS] All playbooks passed syntax check!${NC}"
        ;;
    bootstrap)
        ansible-playbook -i inventory/hosts.ini playbook.yml
        ;;
    cluster)
        ansible-playbook -i inventory/hosts.ini cluster-init.yml
        ;;
    all)
        ansible-playbook -i inventory/hosts.ini site.yml
        ;;
    *)
        echo "Usage: $0 [check|bootstrap|cluster|all]"
        exit 1
        ;;
esac

echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}  Automation Complete! Kubeconfig saved at: ${SCRIPT_DIR}/kubeconfig${NC}"
echo -e "${GREEN}===================================================================${NC}"
