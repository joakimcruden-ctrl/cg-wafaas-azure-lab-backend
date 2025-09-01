param(
    [string] $Subscription
)

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

function Get-TerraformCommand {
    param([string] $FixedDir = "C:\\Program Files\\Terraform")
    $cmd = Get-Command terraform -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
    $candidate = Join-Path $FixedDir "terraform.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "Terraform not found in PATH or at '$FixedDir'. Install Terraform to '$FixedDir' or add it to PATH."
}

function Require-TerraformVersion {
    param([Version] $MinVersion, [string] $TerraformExe)
    $line = (& $TerraformExe version | Select-Object -First 1)
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

function Ensure-AzSubscription {
    param([string] $Desired)

    if ($Desired) {
        Write-Host "Setting Azure subscription to: $Desired"
        & az account set --subscription $Desired --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set Azure subscription to '$Desired'. Use an ID or exact name from 'az account list'."
        }
    }

    $current = az account show -o json --only-show-errors | ConvertFrom-Json
    if (-not $current -or -not $current.id) {
        $subs = az account list -o json --only-show-errors | ConvertFrom-Json
        if (-not $subs -or $subs.Count -eq 0) {
            throw "No Azure subscriptions available for the logged in account."
        }
        if ($subs.Count -eq 1) {
            $only = $subs[0]
            Write-Host "No default subscription set. Using the only available subscription: $($only.name) ($($only.id))"
            & az account set --subscription $only.id --only-show-errors
            if ($LASTEXITCODE -ne 0) { throw "Failed to set Azure subscription to '$($only.id)'." }
        } else {
            $list = $subs | ForEach-Object { "- $($_.name) (`$($_.id)`)" } | Out-String
            throw "No default Azure subscription is set. Re-run with -Subscription '<id or name>'. Available subscriptions:`n$list"
        }
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
${TerraformExe} = Get-TerraformCommand
Require-Command -Name az -InstallHint "Install Azure CLI from https://learn.microsoft.com/cli/azure/install-azure-cli."
Require-TerraformVersion -MinVersion ([Version]::new(1,3,0)) -TerraformExe $TerraformExe
Require-AzLogin
Ensure-AzSubscription -Desired $Subscription
Require-UsersFile -Path $usersFile

Push-Location $tfDir
try {
    Write-Host "Initializing Terraform..."
    & $TerraformExe init -upgrade
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed with exit code $LASTEXITCODE." }

    Write-Host "Applying Terraform..."
    & $TerraformExe apply -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed with exit code $LASTEXITCODE." }

    Write-Host ""
    $credentialsFile = & $TerraformExe output -raw credentials_file
    Write-Host "Deployment complete. Credentials file: $credentialsFile"

    $attackerEndpoint = & $TerraformExe output -json attacker_endpoint
    Write-Host "Attacker endpoint: $attackerEndpoint"

    $apiEndpoints = & $TerraformExe output -json api_endpoints
    Write-Host "API endpoints: $apiEndpoints"
}
finally {
    Pop-Location
}
