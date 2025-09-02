param(
    [string] $Subscription,
    [switch] $Delete,
    [switch] $OnlyAttacker
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
    # Priority: $env:TERRAFORM_EXE -> PATH -> prompt user for path
    $envPath = $env:TERRAFORM_EXE
    if ($envPath) {
        if (Test-Path -LiteralPath $envPath) { return $envPath }
        Write-Warning "TERRAFORM_EXE is set to '$envPath' but does not exist."
    }

    $cmd = Get-Command terraform -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }

    while ($true) {
        $inputPath = Read-Host -Prompt "Enter full path to terraform executable"
        if ([string]::IsNullOrWhiteSpace($inputPath)) { continue }
        if (Test-Path -LiteralPath $inputPath) { return $inputPath }
        Write-Host "Path '$inputPath' does not exist. Try again." -ForegroundColor Yellow
    }
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

function Accept-KaliTerms {
    param([bool] $Enabled)
    if (-not $Enabled) { return }
    try {
        Write-Host "Accepting Kali marketplace terms (if needed)..."
        & az vm image terms accept --publisher kali-linux --offer kali --plan kali --only-show-errors | Out-Null
    } catch {
        Write-Warning "Failed to accept Kali marketplace terms automatically. They may already be accepted, or the CLI lacks permissions."
    }
}

function Get-PrefixFromConfig {
    param([string] $TfDir)
    $tfvars = Join-Path $TfDir "terraform.tfvars"
    if (Test-Path -LiteralPath $tfvars) {
        $line = Get-Content -LiteralPath $tfvars | Where-Object { $_ -match '^\s*prefix\s*=\s*"([^"]+)"' } | Select-Object -First 1
        if ($line) {
            $m = [regex]::Match($line, '^\s*prefix\s*=\s*"([^"]+)"')
            if ($m.Success) { return $m.Groups[1].Value }
        }
    }
    $variables = Join-Path $TfDir "variables.tf"
    if (Test-Path -LiteralPath $variables) {
        $content = Get-Content -LiteralPath $variables -Raw
        $m = [System.Text.RegularExpressions.Regex]::Match($content, 'variable\s+"prefix"[\s\S]*?default\s*=\s*"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return "wafaas-lab"
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
if (-not (Test-Path -LiteralPath ${TerraformExe})) { throw "Terraform executable path '${TerraformExe}' not found." }
Require-Command -Name az -InstallHint "Install Azure CLI from https://learn.microsoft.com/cli/azure/install-azure-cli."
Require-TerraformVersion -MinVersion ([Version]::new(1,3,0)) -TerraformExe $TerraformExe
Require-AzLogin
Ensure-AzSubscription -Desired $Subscription
if (-not $Delete) { Require-UsersFile -Path $usersFile }

# Export subscription context for Terraform provider (defensive)
$acct = az account show -o json --only-show-errors | ConvertFrom-Json
if (-not $acct -or -not $acct.id) {
    throw "Unable to resolve Azure subscription context after selection."
}
Write-Host "Using Azure subscription: $($acct.name) ($($acct.id))"
$env:ARM_SUBSCRIPTION_ID = $acct.id
if ($acct.tenantId) { $env:ARM_TENANT_ID = $acct.tenantId }

Push-Location $tfDir
try {
    Write-Host "Initializing Terraform..."
    & $TerraformExe init -upgrade
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed with exit code $LASTEXITCODE." }

    # Determine if Kali is enabled (default true unless explicitly set false in terraform.tfvars)
    $kaliEnabled = $true
    $tfvarsPath = Join-Path $tfDir "terraform.tfvars"
    if (Test-Path -LiteralPath $tfvarsPath) {
        $content = Get-Content -LiteralPath $tfvarsPath -Raw
        if ($content -match '(?m)^\s*use_kali_attacker\s*=\s*false\b') { $kaliEnabled = $false }
    }
    Accept-KaliTerms -Enabled $kaliEnabled

    if ($Delete) {
        Write-Host "Destroying Terraform-managed resources (auto-approve)..."
        & $TerraformExe destroy -auto-approve
        if ($LASTEXITCODE -ne 0) { Write-Warning "Terraform destroy failed with exit code $LASTEXITCODE. Attempting RG cleanup." }

        $prefix = Get-PrefixFromConfig -TfDir $tfDir
        $rgName = "$prefix-rg"
        Write-Host "Ensuring resource group '$rgName' is deleted..."
        $exists = (& az group exists -n $rgName --only-show-errors).Trim()
        if ($LASTEXITCODE -eq 0 -and $exists -eq 'true') {
            & az group delete -n $rgName --yes --only-show-errors
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to delete resource group '$rgName' via az CLI. It may delete asynchronously or contain non-Terraform resources."
            } else {
                Write-Host "Resource group '$rgName' deletion initiated."
            }
        } else {
            Write-Host "Resource group '$rgName' does not exist or could not be checked."
        }
        return
    }

    Write-Host "Applying Terraform..."
    $tfArgs = @('-auto-approve')
    if ($OnlyAttacker) { $tfArgs += '-var=only_attacker=true' }
    & $TerraformExe apply @tfArgs
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
