#!/usr/bin/env bash
set -euo pipefail

ONLY_ATTACKER=false
if [[ "${1-}" == "-onlyattacker" ]]; then
  ONLY_ATTACKER=true
  shift || true
fi

cd "$(dirname "$0")/../terraform"

echo "Initializing Terraform..."
terraform init -upgrade

echo "Applying Terraform..."
if [[ "$ONLY_ATTACKER" == true ]]; then
  terraform apply -auto-approve -var=only_attacker=true
else
  terraform apply -auto-approve
fi

echo
echo "Deployment complete. Credentials file: $(terraform output -raw credentials_file)"
echo "Attacker endpoint: $(terraform output -json attacker_endpoint)"
echo "API endpoints: $(terraform output -json api_endpoints)"
