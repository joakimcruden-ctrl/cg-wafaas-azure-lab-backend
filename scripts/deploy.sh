#!/usr/bin/env bash
set -euo pipefail

ONLY_ATTACKER=false
if [[ "${1-}" == "-onlyattacker" ]]; then
  ONLY_ATTACKER=true
  shift || true
fi

# Resolve terraform executable
TF_EXE="${TERRAFORM_EXE:-}"
if [[ -n "$TF_EXE" ]]; then
  if [[ ! -x "$TF_EXE" ]]; then
    echo "TERRAFORM_EXE is set to '$TF_EXE' but is not executable."
    TF_EXE=""
  fi
fi

if [[ -z "$TF_EXE" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    TF_EXE="$(command -v terraform)"
  else
    echo "Terraform not found in PATH and TERRAFORM_EXE not set."
    while true; do
      read -r -p "Enter full path to terraform binary: " TF_EXE
      if [[ -x "$TF_EXE" ]]; then
        break
      else
        echo "Provided path '$TF_EXE' is not executable. Try again."
      fi
    done
  fi
fi

# Validate terraform works
if ! "$TF_EXE" version >/dev/null 2>&1; then
  echo "The terraform executable at '$TF_EXE' did not run successfully (version check failed)." >&2
  exit 1
fi

cd "$(dirname "$0")/../terraform"

echo "Initializing Terraform..."
"$TF_EXE" init -upgrade

echo "Applying Terraform..."
if [[ "$ONLY_ATTACKER" == true ]]; then
  "$TF_EXE" apply -auto-approve -var=only_attacker=true
else
  "$TF_EXE" apply -auto-approve
fi

echo
echo "Deployment complete. Credentials file: $($TF_EXE output -raw credentials_file)"
echo "Attacker endpoint: $($TF_EXE output -json attacker_endpoint)"
echo "API endpoints: $($TF_EXE output -json api_endpoints)"
