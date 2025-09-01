#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../terraform"

echo "Initializing Terraform..."
terraform init -upgrade

echo "Applying Terraform..."
terraform apply -auto-approve

echo
echo "Deployment complete. Credentials file: $(terraform output -raw credentials_file)"
echo "Attacker endpoint: $(terraform output -json attacker_endpoint)"
echo "API endpoints: $(terraform output -json api_endpoints)"
