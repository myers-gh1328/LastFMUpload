param(
    [string]$RootDirectory = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$preparedDir = Join-Path $RootDirectory "ExportedData"
$rawDir = Join-Path $RootDirectory "RawData"
$localDir = Join-Path $RootDirectory ".local"
$configPath = Join-Path $localDir "lastfm_config.json"
$sessionPath = Join-Path $localDir "lastfm_session.json"
$prepareScript = Join-Path $PSScriptRoot "prepare-history.ps1"
$uploadScript = Join-Path $PSScriptRoot "scrobble.ps1"

function Get-PreparedFileCount {
    if (-not (Test-Path $preparedDir)) { return 0 }
    return @(Get-ChildItem -Path $preparedDir -Filter "*.json" -File).Count
}

function Invoke-Prepare {
    & $prepareScript -InputDirectory $rawDir -OutputDirectory $preparedDir
}

function Invoke-Upload {
    & $uploadScript -RootDirectory $RootDirectory
}

function Test-LastFmSetup {
    return (Test-Path $configPath) -and (Test-Path $sessionPath)
}

function Invoke-Setup([switch]$Reset) {
    if ($Reset) {
        & $uploadScript -SetupOnly -ResetSetup -RootDirectory $RootDirectory
    } else {
        & $uploadScript -SetupOnly -RootDirectory $RootDirectory
    }
}

Write-Host ""
Write-Host "Spotify to Last.fm Scrobbler"
Write-Host "============================"
Write-Host ""

if (-not (Test-LastFmSetup)) {
    Write-Host "Last.fm setup was not found."
    $setupChoice = Read-Host "Run setup now? (Y/n)"
    if ($setupChoice -notmatch '^(n|no)$') {
        Invoke-Setup
    }
    Write-Host ""
}

$preparedCount = Get-PreparedFileCount

if ($preparedCount -gt 0) {
    Write-Host "Found $preparedCount prepared file(s)."
    Write-Host ""
    Write-Host "1. Upload prepared files to Last.fm"
    Write-Host "2. Prepare listening history from RawData"
    Write-Host "3. Update Last.fm setup"
    Write-Host "4. Exit"
    Write-Host ""
    $choice = Read-Host "Choose an option"

    switch ($choice) {
        "1" { Invoke-Upload }
        "2" { Invoke-Prepare }
        "3" { Invoke-Setup -Reset }
        default { return }
    }
} else {
    Write-Host "No prepared files found."
    Write-Host "Put Spotify JSON or Apple Music CSV files in: $rawDir"
    Write-Host ""
    Write-Host "1. Prepare listening history from RawData"
    Write-Host "2. Update Last.fm setup"
    Write-Host "3. Exit"
    Write-Host ""
    $choice = Read-Host "Choose an option"

    switch ($choice) {
        "1" { Invoke-Prepare }
        "2" { Invoke-Setup -Reset }
        default { return }
    }
}
