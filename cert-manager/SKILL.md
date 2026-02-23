# Cert Manager Skill

Automated wildcard SSL certificate renewal and distribution for `*.pund-it.ca`.

## Architecture

```
Linux (this server)              Windows Servers
┌─────────────────┐              ┌──────────────────┐
│ acme.sh         │──── DNS-01──→│ cPanel/WHM       │
│ (renew cert)    │              │ cpanel9.indieserve│
│                 │              └──────────────────┘
│ Export PFX      │
│                 │──── SCP ────→ punsvscnfdc (Veeam CC + SC)
│                 │──── SCP ────→ punsvkinf-spc (Veeam CC)
│                 │──── SCP ────→ punsvkinfcg (Veeam CC)
│                 │──── SCP ────→ punsvoffki-nfr (Veeam CC)
│                 │──── SCP ────→ punsvkiv2nf-nfr (Veeam CC)
│                 │──── SCP ────→ help.pund-it.ca (SC)
└─────────────────┘
```

## Setup

### 1. Configure credentials
Edit `config/servers.json`:
- Set `cpanel.username` (WHM root user or cPanel user that owns pund-it.ca DNS)
- Set `cpanel.apiToken` (generate in WHM > API Tokens or cPanel > Security > API Tokens)

### 2. Ensure SSH access
Each Windows server needs OpenSSH Server enabled. Test with:
```bash
ssh administrator@10.255.71.42 "echo ok"
```

### 3. First run (issue cert)
```bash
# Test with staging first (no rate limits)
bash scripts/renew-cert.sh --staging

# Then issue for real
bash scripts/renew-cert.sh --force
```

## Scripts

### renew-cert.sh — Issue/renew the wildcard cert
```bash
./scripts/renew-cert.sh              # Renew if needed
./scripts/renew-cert.sh --force      # Force renewal
./scripts/renew-cert.sh --staging    # Use Let's Encrypt staging (testing)
```
Outputs: `certs/wildcard.pfx`, `certs/fullchain.pem`, `certs/key.pem`, `certs/metadata.json`

### distribute-cert.sh — Push cert to all servers
```bash
./scripts/distribute-cert.sh                     # All servers
./scripts/distribute-cert.sh --server punsvscnfdc # Specific server
./scripts/distribute-cert.sh --role veeam-cc      # Only Veeam servers
./scripts/distribute-cert.sh --role screenconnect  # Only ScreenConnect servers
./scripts/distribute-cert.sh --dry-run            # Preview only
./scripts/distribute-cert.sh --user wayne         # Custom SSH user
```

### full-renewal.sh — Complete lifecycle (renew + distribute)
```bash
./scripts/full-renewal.sh            # Standard renewal + push
./scripts/full-renewal.sh --force    # Force renewal + push
./scripts/full-renewal.sh --dry-run  # Preview everything
```

## Adding New Servers

Edit `config/servers.json` and add to the `servers` array:
```json
{
  "name": "new-server",
  "ip": "10.255.x.x",
  "roles": ["veeam-cc"],
  "enabled": true
}
```

### Supported Roles
- **veeam-cc** — Veeam Cloud Connect (imports cert, applies via Veeam PowerShell)
- **screenconnect** — ConnectWise ScreenConnect (netsh SSL binding + service restart)

### Adding New Roles
Create a new PowerShell script in `scripts/powershell/apply-<role>.ps1` and add a case in `distribute-cert.sh`.

## Automation (Cron)

Schedule monthly renewal via OpenClaw cron:
```
Task: Run full-renewal.sh for *.pund-it.ca wildcard cert
Schedule: 1st of each month at 3am
```

Let's Encrypt certs are valid for 90 days. Monthly renewal gives plenty of buffer.

## Veeam Cloud Connect Notes

- Registry key `CloudIgnoreInaccessibleKey=1` is set automatically (needed for LE certs)
- Uses `Add-VBRCloudGatewayCertificate` PowerShell cmdlet
- Veeam services may need a one-time restart after first registry key change
- Old certs are cleaned up automatically (keeps last 2)

## ScreenConnect Notes

- Uses `netsh http update sslcert` with appid `{00000000-0000-0000-0000-000000000000}`
- Falls back to delete+add if update fails
- Restarts all ScreenConnect/ConnectWise Control services automatically

## Cert Storage

All cert files are in `certs/`:
- `wildcard.pfx` — PKCS12 for Windows import
- `fullchain.pem` — Full chain (cert + intermediates)
- `key.pem` — Private key
- `cert.pem` — Certificate only
- `ca.pem` — CA chain
- `metadata.json` — Thumbprint, expiry, renewal date
- `thumbprint.txt` — SHA1 thumbprint (for quick reference)

## Troubleshooting

### DNS challenge fails
- Verify cPanel API token has DNS zone edit permissions
- Check: `curl -sk -H "Authorization: whm root:TOKEN" "https://cpanel9.indieserve.net:2087/json-api/listaccts"`
- Ensure `_acme-challenge.pund-it.ca` TXT record can be created

### Veeam cert not applying
- Check Veeam PowerShell module is installed: `Get-Module -ListAvailable Veeam*`
- Verify CloudIgnoreInaccessibleKey registry key exists
- Try manual: Open Veeam Console > Cloud Connect > Manage Certificate

### ScreenConnect binding fails
- Check current binding: `netsh http show sslcert ipport=0.0.0.0:443`
- Verify cert is in store: `Get-ChildItem Cert:\LocalMachine\My | Where Thumbprint -eq <thumbprint>`
