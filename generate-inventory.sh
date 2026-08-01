#!/usr/bin/env bash
# Generates ansible/inventory/hosts.ini from Terraform outputs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${ROOT}/terraform"
INV="${ROOT}/ansible/inventory/hosts.ini"
KEY="${SSH_KEY_PATH:-$HOME/.ssh/travelmemory}"

WEB_PUBLIC=$(terraform -chdir="${TF_DIR}" output -raw web_public_ip)
WEB_PRIVATE=$(terraform -chdir="${TF_DIR}" output -raw web_private_ip)
DB_PRIVATE=$(terraform -chdir="${TF_DIR}" output -raw db_private_ip)

cat > "${INV}" <<INVENTORY
[web]
${WEB_PUBLIC} ansible_user=ubuntu

[db]
${DB_PRIVATE} ansible_user=ubuntu

[db:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ${KEY} -W %h:%p -q -o StrictHostKeyChecking=no ubuntu@${WEB_PUBLIC}" -o StrictHostKeyChecking=no'

[all:vars]
ansible_ssh_private_key_file=${KEY}
web_public_ip=${WEB_PUBLIC}
web_private_ip=${WEB_PRIVATE}
db_private_ip=${DB_PRIVATE}
INVENTORY

echo "Wrote ${INV}"
cat "${INV}"
