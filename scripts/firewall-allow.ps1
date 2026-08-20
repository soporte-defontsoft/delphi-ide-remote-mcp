<#
  firewall-allow.ps1 - stop Windows Firewall asking every time the server starts.

  Windows keys its "allow" prompts to the EXE binary, so every rebuild looks
  like a new program and prompts again - and binding to all interfaces prompts
  twice (IPv4 + IPv6). This creates ONE persistent inbound rule keyed to the
  PORT instead, which covers any rebuild forever, and removes the pile of
  per-binary duplicates left behind.

  Run ONCE, as Administrator:
      powershell -ExecutionPolicy Bypass -File scripts\firewall-allow.ps1 -Port 3131

  To undo:
      powershell -ExecutionPolicy Bypass -File scripts\firewall-allow.ps1 -Port 3131 -Remove
#>
param(
  [int]$Port = 3131,
  [switch]$Remove
)

$ruleName = "DelphiLspMcp (TCP $Port)"

# must be elevated to touch the firewall
$admin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Write-Host "This needs Administrator. Re-run in an elevated PowerShell." -ForegroundColor Yellow
  exit 1
}

# 1) remove the per-binary rules the "allow this app?" dialog left behind.
# Windows decides per program PATH, so every copy of the exe in a different
# folder is a separate rule - and a rule survives the folder being deleted.
# The right rule is the port one created below, not these.
$stale = Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue |
  Where-Object { $_.Program -match 'DelphiLspMcp\.exe$' }
$removed = 0
foreach ($f in $stale) {
  try { $f | Get-NetFirewallRule | Remove-NetFirewallRule -ErrorAction Stop; $removed++ } catch {}
}
if ($removed) { Write-Host "Removed $removed stale per-binary rule(s)." -ForegroundColor Green }

# also clear our own port rule so we can recreate it cleanly / honour -Remove
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
  Remove-NetFirewallRule -ErrorAction SilentlyContinue

if ($Remove) {
  Write-Host "Removed the port rule '$ruleName'. Windows will prompt again next start." -ForegroundColor Green
  exit 0
}

# 2) one durable rule keyed to the PORT (covers every rebuild)
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort $Port -Profile Any | Out-Null

Write-Host "Allowed inbound TCP $Port as '$ruleName'." -ForegroundColor Green
Write-Host "No more prompts for this port - rebuilds included." -ForegroundColor Green
Write-Host "Tip: set [Server] BindIP to your LAN/VPN address to also avoid the IPv4+IPv6 double prompt." -ForegroundColor DarkGray
