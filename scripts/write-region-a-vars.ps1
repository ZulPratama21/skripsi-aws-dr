# Run after Region-B apply and before Region-A plan.
# Writes non-secret input to gitignored Region-A/dr.auto.tfvars.
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$regionB = Join-Path $repo "Region-B"
$regionA = Join-Path $repo "Region-A"
Push-Location $regionB
try {
  $ip = (terraform output -raw region_b_eip).Trim()
  $parsed = $null
  if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw "Region B output is not a valid IPv4 address: $ip"
  }
} finally { Pop-Location }
$dest = Join-Path $regionA 'dr.auto.tfvars'
Set-Content -Path $dest -Value ('region_b_elastic_ip = "{0}"' -f $ip) -Encoding ascii
Write-Host "Wrote Region A input: $dest -> $ip"
Write-Host "Do not commit dr.auto.tfvars; it should be ignored by .gitignore."
