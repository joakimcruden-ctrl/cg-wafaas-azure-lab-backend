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

# Determine location and Kali flag from tfvars
LOCATION="westeurope"
if [[ -f terraform.tfvars ]]; then
  if grep -Eq '^\s*location\s*=\s*"[^"]+"' terraform.tfvars; then
    LOCATION=$(sed -n 's/^\s*location\s*=\s*"\([^"]\+\)".*/\1/p' terraform.tfvars | head -n1)
  fi
fi

USE_KALI=true
if [[ -f terraform.tfvars ]] && grep -Eq '^\s*use_kali_attacker\s*=\s*false\b' terraform.tfvars; then
  USE_KALI=false
fi

# Check Kali image availability in region; fallback to Ubuntu if unavailable
TF_EXTRA_ARGS=()
if [[ "$USE_KALI" == true ]]; then
  if command -v az >/dev/null 2>&1; then
    echo "Checking Kali image availability in region '$LOCATION'..."
    LIST_OUT=$(az vm image list --publisher kali-linux --offer kali --sku kali --location "$LOCATION" --all --only-show-errors -o tsv --query "[].name" || true)
    if [[ -z "$LIST_OUT" ]]; then
      echo "Kali image not available in region '$LOCATION'. Falling back to Ubuntu attacker."
      USE_KALI=false
      TF_EXTRA_ARGS+=("-var=use_kali_attacker=false")
    else
      echo "Accepting Kali marketplace terms (if needed)..."
      az vm image terms accept --publisher kali-linux --offer kali --plan kali --only-show-errors >/dev/null 2>&1 || true
    fi
  else
    echo "Azure CLI not found; cannot verify Kali availability or accept terms. Proceeding; if apply fails, set use_kali_attacker=false."
  fi
fi

echo "Applying Terraform..."
APPLY_ARGS=("-auto-approve")
if [[ "$ONLY_ATTACKER" == true ]]; then APPLY_ARGS+=("-var=only_attacker=true"); fi
if (( ${#TF_EXTRA_ARGS[@]} > 0 )); then APPLY_ARGS+=("${TF_EXTRA_ARGS[@]}"); fi
"$TF_EXE" apply "${APPLY_ARGS[@]}"

echo
echo "Deployment complete. Credentials file: $($TF_EXE output -raw credentials_file)"
echo "Attacker endpoint: $($TF_EXE output -json attacker_endpoint)"
echo "API endpoints: $($TF_EXE output -json api_endpoints)"
