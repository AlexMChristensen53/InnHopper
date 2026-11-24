# Builds a release zip without developer files.
# Usage: powershell -ExecutionPolicy Bypass -File .\release.ps1
$ErrorActionPreference = "Stop"

# Located in "<addon>\Developer stuff"; the addon folder is the parent.
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$src     = Split-Path -Parent $here
$tocPath = Join-Path $src "InnHopper.toc"

# Version from the .toc
$match = Select-String -Path $tocPath -Pattern '^## Version:\s*(.+)$'
if (-not $match) { throw "No '## Version:' line found in InnHopper.toc" }
$version = $match.Matches[0].Groups[1].Value.Trim()

# Stage a temporary copy
$staging = Join-Path $env:TEMP ("InnHopper-release-" + [guid]::NewGuid().ToString("N"))
$dest    = Join-Path $staging "InnHopper"
New-Item -ItemType Directory -Path $dest | Out-Null
# Copy all except developer files
Get-ChildItem -Path $src -Force | Where-Object { $_.Name -ne "Developer stuff" -and $_.Name -ne ".git" -and $_.Name -ne ".pkgmeta" } |
  Copy-Item -Destination $dest -Recurse

# Remove Debug.lua and the toc lines loading it
Remove-Item (Join-Path $dest "Debug.lua") -ErrorAction SilentlyContinue
$lines = Get-Content (Join-Path $dest "InnHopper.toc")
$kept  = @()
$skip  = $false
foreach ($line in $lines) {
  if ($line -match '^#@debug@')     { $skip = $true;  continue }
  if ($line -match '^#@end-debug@') { $skip = $false; continue }
  if (-not $skip) { $kept += $line }
}
[System.IO.File]::WriteAllLines((Join-Path $dest "InnHopper.toc"), $kept, (New-Object System.Text.UTF8Encoding($false)))

# Create the zip
$zip = Join-Path $here ("InnHopper-" + $version + ".zip")
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $dest -DestinationPath $zip
Remove-Item $staging -Recurse -Force

Write-Host "Built $zip"
