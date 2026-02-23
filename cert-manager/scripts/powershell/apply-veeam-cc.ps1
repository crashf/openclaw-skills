# Apply wildcard cert to Veeam Cloud Connect
# Usage: apply-veeam-cc.ps1 -PfxPath <path> -PfxPassword <password> -Thumbprint <thumbprint>
#
# Steps:
#   1. Import PFX to LocalMachine\My certificate store
#   2. Connect to local Veeam B&R server
#   3. Get the cert from store by thumbprint
#   4. Apply to Cloud Connect gateway
#   5. Clean up old certs (optional)

param(
    [Parameter(Mandatory=$true)]
    [string]$PfxPath,
    
    [Parameter(Mandatory=$true)]
    [string]$PfxPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$Thumbprint
)

$ErrorActionPreference = "Stop"

Write-Host "=== Veeam Cloud Connect Certificate Update ===" -ForegroundColor Cyan
Write-Host "PFX: $PfxPath"
Write-Host "Thumbprint: $Thumbprint"

# Step 1: Ensure registry key exists for LE certs
# This prevents Veeam from checking private key exportability (fails with LE certs)
$regPath = "HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication"
$regName = "CloudIgnoreInaccessibleKey"
if (Test-Path $regPath) {
    $currentVal = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    if ($null -eq $currentVal -or $currentVal.$regName -ne 1) {
        Write-Host "Setting CloudIgnoreInaccessibleKey registry value..." -ForegroundColor Yellow
        Set-ItemProperty -Path $regPath -Name $regName -Value 1 -Type DWord
        Write-Host "  Registry key set. Note: Veeam services may need restart on first run."
    }
}

# Step 2: Import PFX to certificate store
Write-Host "`nImporting certificate..." -ForegroundColor Cyan
$securePass = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force

# Check if cert already exists in store
$existingCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $Thumbprint }
if ($existingCert) {
    Write-Host "  Certificate already in store (thumbprint match)"
} else {
    $imported = Import-PfxCertificate -FilePath $PfxPath -Password $securePass -CertStoreLocation Cert:\LocalMachine\My -Exportable
    Write-Host "  Imported: $($imported.Subject) (Thumbprint: $($imported.Thumbprint))"
}

# Step 3: Load Veeam PowerShell snapin
Write-Host "`nLoading Veeam PowerShell module..." -ForegroundColor Cyan
try {
    # Try module first (v12+)
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
    Write-Host "  Loaded Veeam.Backup.PowerShell module"
} catch {
    try {
        # Fall back to snapin (older versions)
        Add-PSSnapin VeeamPSSnapin -ErrorAction Stop
        Write-Host "  Loaded VeeamPSSnapin"
    } catch {
        Write-Host "  WARNING: Could not load Veeam PowerShell. Cert imported to store but NOT applied to Cloud Connect." -ForegroundColor Yellow
        Write-Host "  Apply manually: Veeam Console > Cloud Connect > Manage Certificate"
        exit 0
    }
}

# Step 4: Connect to local Veeam server
Write-Host "`nConnecting to Veeam B&R server..." -ForegroundColor Cyan
try {
    Connect-VBRServer -Server localhost
    Write-Host "  Connected"
} catch {
    Write-Host "  WARNING: Could not connect to Veeam server. Cert imported but NOT applied." -ForegroundColor Yellow
    Write-Host "  Error: $_"
    exit 0
}

# Step 5: Apply certificate to Cloud Connect
Write-Host "`nApplying certificate to Cloud Connect..." -ForegroundColor Cyan
try {
    $cert = Get-VBRCloudGatewayCertificate -FromStore | Where-Object { $_.Thumbprint -eq $Thumbprint }
    
    if ($null -eq $cert) {
        Write-Host "  ERROR: Certificate with thumbprint $Thumbprint not found in Veeam certificate list" -ForegroundColor Red
        Write-Host "  Available certificates:"
        Get-VBRCloudGatewayCertificate -FromStore | ForEach-Object {
            Write-Host "    $($_.SubjectName) - $($_.Thumbprint)"
        }
        Disconnect-VBRServer
        exit 1
    }
    
    Add-VBRCloudGatewayCertificate -Certificate $cert
    Write-Host "  Certificate applied successfully!" -ForegroundColor Green
} catch {
    Write-Host "  ERROR applying certificate: $_" -ForegroundColor Red
    Disconnect-VBRServer
    exit 1
}

# Step 6: Disconnect
Disconnect-VBRServer
Write-Host "`n✅ Veeam Cloud Connect certificate updated" -ForegroundColor Green

# Step 7: Clean up old wildcard certs from store (keep last 2)
Write-Host "`nCleaning up old certificates..." -ForegroundColor Cyan
$wildcardCerts = Get-ChildItem -Path Cert:\LocalMachine\My | 
    Where-Object { $_.Subject -like "*pund-it.ca*" } | 
    Sort-Object NotAfter -Descending

if ($wildcardCerts.Count -gt 2) {
    $toRemove = $wildcardCerts | Select-Object -Skip 2
    foreach ($oldCert in $toRemove) {
        Write-Host "  Removing old cert: $($oldCert.Subject) (Expires: $($oldCert.NotAfter))"
        Remove-Item -Path "Cert:\LocalMachine\My\$($oldCert.Thumbprint)" -Force
    }
}

Write-Host "`nDone!" -ForegroundColor Green
