# Apply wildcard cert to ScreenConnect (ConnectWise Control)
# Usage: apply-screenconnect.ps1 -PfxPath <path> -PfxPassword <password> -Thumbprint <thumbprint>
#
# Steps:
#   1. Import PFX to LocalMachine\My certificate store
#   2. Update SSL binding on 0.0.0.0:443 using netsh
#   3. Restart ScreenConnect services

param(
    [Parameter(Mandatory=$true)]
    [string]$PfxPath,
    
    [Parameter(Mandatory=$true)]
    [string]$PfxPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$Thumbprint
)

$ErrorActionPreference = "Stop"

Write-Host "=== ScreenConnect Certificate Update ===" -ForegroundColor Cyan
Write-Host "PFX: $PfxPath"
Write-Host "Thumbprint: $Thumbprint"

# Step 1: Import PFX to certificate store
Write-Host "`nImporting certificate..." -ForegroundColor Cyan
$securePass = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force

$existingCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $Thumbprint }
if ($existingCert) {
    Write-Host "  Certificate already in store"
} else {
    $imported = Import-PfxCertificate -FilePath $PfxPath -Password $securePass -CertStoreLocation Cert:\LocalMachine\My -Exportable
    Write-Host "  Imported: $($imported.Subject) (Thumbprint: $($imported.Thumbprint))"
}

# Step 2: Check current SSL binding
Write-Host "`nChecking current SSL binding..." -ForegroundColor Cyan
$currentBinding = netsh http show sslcert ipport=0.0.0.0:443 2>&1
Write-Host "  Current binding:"
Write-Host "  $currentBinding"

# Step 3: Update SSL binding
Write-Host "`nUpdating SSL binding..." -ForegroundColor Cyan

# Remove lowercase thumbprint formatting (netsh wants no colons, no spaces)
$cleanThumbprint = $Thumbprint -replace '[:\s]', ''

# Try update first, fall back to delete+add
try {
    $result = netsh http update sslcert ipport="0.0.0.0:443" certhash="$cleanThumbprint" appid="{00000000-0000-0000-0000-000000000000}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "netsh update failed: $result"
    }
    Write-Host "  SSL binding updated" -ForegroundColor Green
} catch {
    Write-Host "  Update failed, trying delete+add..." -ForegroundColor Yellow
    
    # Delete existing binding
    netsh http delete sslcert ipport="0.0.0.0:443" 2>&1 | Out-Null
    
    # Add new binding
    $result = netsh http add sslcert ipport="0.0.0.0:443" certhash="$cleanThumbprint" appid="{00000000-0000-0000-0000-000000000000}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to add SSL binding: $result" -ForegroundColor Red
        exit 1
    }
    Write-Host "  SSL binding added" -ForegroundColor Green
}

# Step 4: Restart ScreenConnect services
Write-Host "`nRestarting ScreenConnect services..." -ForegroundColor Cyan

$scServices = Get-Service | Where-Object { $_.Name -like "*ScreenConnect*" -or $_.DisplayName -like "*ScreenConnect*" -or $_.Name -like "*ConnectWise Control*" }

if ($scServices.Count -eq 0) {
    Write-Host "  WARNING: No ScreenConnect services found. Checking for alternate names..." -ForegroundColor Yellow
    $scServices = Get-Service | Where-Object { $_.Name -like "*Control*Server*" }
}

if ($scServices.Count -gt 0) {
    foreach ($svc in $scServices) {
        Write-Host "  Restarting: $($svc.DisplayName) ($($svc.Name))"
        Restart-Service -Name $svc.Name -Force
        Start-Sleep -Seconds 2
    }
    Write-Host "  Services restarted" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Could not find ScreenConnect services to restart" -ForegroundColor Yellow
    Write-Host "  You may need to restart manually"
}

# Step 5: Verify
Write-Host "`nVerifying new binding..." -ForegroundColor Cyan
$newBinding = netsh http show sslcert ipport=0.0.0.0:443 2>&1
Write-Host "  $newBinding"

# Step 6: Clean up old wildcard certs (keep last 2)
Write-Host "`nCleaning up old certificates..." -ForegroundColor Cyan
$wildcardCerts = Get-ChildItem -Path Cert:\LocalMachine\My | 
    Where-Object { $_.Subject -like "*pund-it.ca*" } | 
    Sort-Object NotAfter -Descending

if ($wildcardCerts.Count -gt 2) {
    $toRemove = $wildcardCerts | Select-Object -Skip 2
    foreach ($oldCert in $toRemove) {
        if ($oldCert.Thumbprint -ne $cleanThumbprint) {
            Write-Host "  Removing old cert: $($oldCert.Subject) (Expires: $($oldCert.NotAfter))"
            Remove-Item -Path "Cert:\LocalMachine\My\$($oldCert.Thumbprint)" -Force
        }
    }
}

Write-Host "`n✅ ScreenConnect certificate updated" -ForegroundColor Green
