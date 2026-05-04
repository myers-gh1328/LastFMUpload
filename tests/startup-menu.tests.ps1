$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "src/Start-LastFM-Upload.ps1"
$sandbox = Join-Path $PSScriptRoot "tmp-startup-menu"

function Assert-MatchText([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

if (Test-Path $sandbox) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}

New-Item -ItemType Directory -Path $sandbox | Out-Null

$output = @("n", "4") | pwsh -NoProfile -File $scriptPath -RootDirectory $sandbox 2>&1 | Out-String

Assert-MatchText $output "Last\.fm setup was not found" "Startup did not report missing setup."
Assert-MatchText $output "Update Last\.fm setup" "Menu did not include update setup option."

Remove-Item -LiteralPath $sandbox -Recurse -Force
Write-Host "startup menu tests passed"
