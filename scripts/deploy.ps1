$ErrorActionPreference = "Stop"

# Resolve repo paths relative to this script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tfDir = Join-Path $scriptDir "..\terraform"

Push-Location $tfDir
try {
    Write-Host "Initializing Terraform..."
    terraform init -upgrade

    Write-Host "Applying Terraform..."
    terraform apply -auto-approve

    Write-Host ""
    $credentialsFile = terraform output -raw credentials_file
    Write-Host "Deployment complete. Credentials file: $credentialsFile"

    $attackerEndpoint = terraform output -json attacker_endpoint
    Write-Host "Attacker endpoint: $attackerEndpoint"

    $apiEndpoints = terraform output -json api_endpoints
    Write-Host "API endpoints: $apiEndpoints"
}
finally {
    Pop-Location
}

