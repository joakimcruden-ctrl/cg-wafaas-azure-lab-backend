$ErrorActionPreference = "Stop"

function Require-Command {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $InstallHint
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        if ($InstallHint) {
            throw "Required command '$Name' not found in PATH. $InstallHint"
        } else {
            throw "Required command '$Name' not found in PATH."
        }
    }
}

function Require-TerraformVersion {
    param([Version] $MinVersion)
    $line = (& terraform version | Select-Object -First 1)
    if (-not $line) { throw "Unable to determine Terraform version." }
    if ($line -match 'v?([0-9]+)\.([0-9]+)\.([0-9]+)') {
        $ver = [Version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        if ($ver -lt $MinVersion) {
            throw "Terraform $ver found; require >= $MinVersion."
        }
    } else {
        Write-Warning "Could not parse Terraform version from: '$line'"
    }
}

function Require-AzLogin {
    # Check that the user is logged in to Azure CLI
    $null = & az account show --only-show-errors 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI is installed but not logged in. Run 'az login' and try again."
    }
}

function Require-UsersFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required users file not found: $Path"
    }
    $nonEmpty = Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
    if (-not $nonEmpty) {
        throw "The users file ($Path) has no non-empty lines. Add one username per line."
    }
}

# Resolve repo paths relative to this script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir "..")
$tfDir     = Join-Path $repoRoot "terraform"
$usersFile = Join-Path $repoRoot "users.txt"

# Dependency and environment checks
Write-Host "Checking prerequisites..."
Require-Command -Name terraform -InstallHint "Install from https://developer.hashicorp.com/terraform/downloads and ensure it's in PATH."
Require-Command -Name az -InstallHint "Install Azure CLI from https://learn.microsoft.com/cli/azure/install-azure-cli."
Require-TerraformVersion -MinVersion ([Version]::new(1,3,0))
Require-AzLogin
Require-UsersFile -Path $usersFile

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
