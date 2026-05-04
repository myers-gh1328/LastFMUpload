# Spotify -> Last.fm Scrobbler
# Usage: Just run .\scrobble.ps1 and follow the prompts.
# Credentials and session are stored in .lastfm_config and .lastfm_session
# (kept out of the script itself).

param(
    [int]$BatchSize = 50,
    [int]$DelayMs = 1500,
    [switch]$Debug,
    [switch]$SetupOnly,
    [switch]$ResetSetup,
    [string]$RootDirectory = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$localDir = Join-Path $RootDirectory ".local"
$configPath = Join-Path $localDir "lastfm_config.json"
$sessionPath = Join-Path $localDir "lastfm_session.json"
$dataDir = Join-Path $RootDirectory "ExportedData"
$doneDir = Join-Path $RootDirectory "Uploaded"
$apiBase = "https://ws.audioscrobbler.com/2.0/"

# --- MD5 helper ---
function Get-MD5String([string]$text) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = $md5.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
}

# --- API signature ---
function Get-ApiSig($params, [string]$secret) {
    # Must use byte-level (ordinal) sort — Last.fm requires ASCII order, e.g. artist[10] < artist[1]
    # Sort-Object with any Culture flag treats [] as insignificant and gives wrong order for multi-digit indices.
    $keys = [string[]]@($params.Keys)
    [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
    $sigString = ""
    foreach ($key in $keys) { $sigString += "$key$($params[$key])" }
    $sigString += $secret
    if ($script:Debug) {
        Write-Host "`n  DEBUG sig input: $($sigString.Substring(0, [Math]::Min(200, $sigString.Length)))..." -ForegroundColor DarkYellow
        Write-Host "  DEBUG sig hash:  $(Get-MD5String $sigString)" -ForegroundColor DarkYellow
    }
    return Get-MD5String $sigString
}

# --- Load or set up credentials ---
function Get-Credentials {
    if ($ResetSetup -and (Test-Path $configPath)) {
        Remove-Item -LiteralPath $configPath -Force
    }

    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        Write-Host "Loaded API credentials from .lastfm_config" -ForegroundColor Green
        return @{ ApiKey = $config.ApiKey; ApiSecret = $config.ApiSecret }
    }

    Write-Host "`n=== Last.fm API Setup ===" -ForegroundColor Cyan
    Write-Host "Create an API account at: https://www.last.fm/api/account/create"
    Write-Host "Set the callback URL to: http://localhost`n"

    $key = Read-Host "Enter your API Key"
    $secret = Read-Host "Enter your Shared Secret"

    if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir | Out-Null }
    @{ ApiKey = $key; ApiSecret = $secret } | ConvertTo-Json | Set-Content $configPath
    Write-Host "Credentials saved.`n" -ForegroundColor Green
    return @{ ApiKey = $key; ApiSecret = $secret }
}

# --- Authenticate ---
function Get-SessionKey([string]$apiKey, [string]$apiSecret) {
    if ($ResetSetup -and (Test-Path $sessionPath)) {
        Remove-Item -LiteralPath $sessionPath -Force
    }

    if (Test-Path $sessionPath) {
        $saved = Get-Content $sessionPath -Raw | ConvertFrom-Json
        Write-Host "Using saved session for: $($saved.Name)" -ForegroundColor Green
        return $saved.Key
    }

    Write-Host "`n=== Authentication ===" -ForegroundColor Cyan

    # Step 1: Get token (api_sig required per Last.fm desktop auth spec)
    $tokenSigParams = New-Object 'System.Collections.Generic.SortedDictionary[string,string]'
    $tokenSigParams["api_key"] = $apiKey
    $tokenSigParams["method"] = "auth.getToken"
    $tokenSig = Get-ApiSig $tokenSigParams $apiSecret
    $resp = Invoke-RestMethod -Uri "$apiBase`?method=auth.getToken&api_key=$([uri]::EscapeDataString($apiKey))&api_sig=$tokenSig&format=json"
    $token = $resp.token

    # Step 2: User approves in browser
    $authUrl = "https://www.last.fm/api/auth/?api_key=$apiKey&token=$token"
    Write-Host "Opening your browser to approve access..."
    Start-Process $authUrl
    Write-Host "`nAfter approving in your browser, press Enter here..." -ForegroundColor Yellow
    Read-Host

    # Step 3: Get session
    $sessParams = New-Object 'System.Collections.Generic.SortedDictionary[string,string]' ([System.StringComparer]::Ordinal)
    $sessParams["method"] = "auth.getSession"
    $sessParams["api_key"] = $apiKey
    $sessParams["token"] = $token
    $sig = Get-ApiSig $sessParams $apiSecret
    $sessParams["api_sig"] = $sig
    $sessParams["format"] = "json"

    $qs = ($sessParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join '&'
    $resp = Invoke-RestMethod -Uri "$apiBase`?$qs"

    if ($resp.error) {
        Write-Host "Auth failed: $($resp.message)" -ForegroundColor Red
        exit 1
    }

    $sk = $resp.session.key
    $name = $resp.session.name

    if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir | Out-Null }
    @{ Key = $sk; Name = $name } | ConvertTo-Json | Set-Content $sessionPath
    Write-Host "Authenticated as $name. Session saved.`n" -ForegroundColor Green
    return $sk
}

# --- Interactive file picker ---
function Select-ExportFile {
    if (-not (Test-Path $dataDir)) {
        Write-Host "ExportedData folder not found at: $dataDir" -ForegroundColor Red
        exit 1
    }

    $files = Get-ChildItem -Path $dataDir -Filter "*.json" | Sort-Object Name
    if ($files.Count -eq 0) {
        Write-Host "No JSON files found in ExportedData." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n=== Select a file to scrobble ===" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        # Parse the date from the filename for a friendly display
        $datePart = $f.BaseName -replace 'T', ' ' -replace 'Z', ''
        $sizeMB = [Math]::Round($f.Length / 1MB, 1)
        Write-Host ("  [{0,2}]  {1}  ({2} MB)" -f ($i + 1), $datePart, $sizeMB) -ForegroundColor White
    }
    Write-Host ""

    do {
        $choice = Read-Host "Enter a number (1-$($files.Count))"
        $num = 0
        $valid = [int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $files.Count
        if (-not $valid) { Write-Host "Invalid choice, try again." -ForegroundColor Yellow }
    } while (-not $valid)

    return $files[$num - 1].FullName
}

# --- Scrobble a batch ---
function Send-Batch([array]$tracks, [string]$apiKey, [string]$apiSecret, [string]$sessionKey, [int64]$baseTimestamp, [int]$startIndex) {
    # Use SortedDictionary with Ordinal comparer for strict ASCII sort order
    $params = New-Object 'System.Collections.Generic.SortedDictionary[string,string]' ([System.StringComparer]::Ordinal)
    $params["method"] = "track.scrobble"
    $params["api_key"] = $apiKey
    $params["sk"] = $sessionKey

    for ($j = 0; $j -lt $tracks.Count; $j++) {
        $t = $tracks[$j]
        $ts = $baseTimestamp + $startIndex + $j
        $params["artist[$j]"] = [string]$t.artistName
        $params["track[$j]"] = [string]$t.trackName
        # Only include album if it has a value - empty optional params can break the sig
        if ($t.albumName) { $params["album[$j]"] = [string]$t.albumName }
        $params["timestamp[$j]"] = $ts.ToString()
    }

    # Build signature (exclude 'format' from sig)
    $sig = Get-ApiSig $params $apiSecret
    $params["api_sig"] = $sig
    $params["format"] = "json"

    # POST body
    $bodyParts = @()
    foreach ($kv in $params.GetEnumerator()) {
        $bodyParts += "$($kv.Key)=$([uri]::EscapeDataString($kv.Value))"
    }
    $body = $bodyParts -join '&'

    if ($script:Debug) {
        Write-Host "  DEBUG POST body (first 300 chars): $($body.Substring(0, [Math]::Min(300, $body.Length)))..." -ForegroundColor DarkYellow
    }

    $resp = Invoke-RestMethod -Uri $apiBase -Method Post -Body $body -ContentType "application/x-www-form-urlencoded; charset=utf-8"
    return $resp
}

# --- Main ---
Write-Host "`n  Spotify -> Last.fm Scrobbler" -ForegroundColor Magenta
Write-Host "  ============================`n"

$creds = Get-Credentials
$sk = Get-SessionKey $creds.ApiKey $creds.ApiSecret

if ($SetupOnly) {
    Write-Host "`nLast.fm setup is ready." -ForegroundColor Green
    exit 0
}

$filePath = Select-ExportFile

Write-Host "`nLoading $([System.IO.Path]::GetFileName($filePath))..." -ForegroundColor Cyan
$data = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json

# Sort oldest first
$data = $data | Sort-Object { [DateTime]::Parse($_.time) }
$total = $data.Count
Write-Host "$total tracks loaded."
Write-Host "  Oldest: $($data[0].time)"
Write-Host "  Newest: $($data[-1].time)"
Write-Host "  Sample: artist='$($data[0].artistName)' track='$($data[0].trackName)'" -ForegroundColor Cyan
Write-Host "`nScrobbling in batches of $BatchSize with ${DelayMs}ms delay..."
Write-Host "Press Ctrl+C to stop at any time.`n"

$sent = 0
$accepted = 0
$ignored = 0
$errors = 0

# All tracks get yesterday's date as timestamp, 1 second apart to keep them unique and ordered
$baseTimestamp = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) - 86400

for ($i = 0; $i -lt $total; $i += $BatchSize) {
    $end = [Math]::Min($i + $BatchSize, $total)
    $batch = $data[$i..($end - 1)]
    $batchNum = [Math]::Floor($i / $BatchSize) + 1

    try {
        $result = Send-Batch $batch $creds.ApiKey $creds.ApiSecret $sk $baseTimestamp $i

        if ($result.error) {
            Write-Host "  ERROR batch ${batchNum}: $($result.message)" -ForegroundColor Red
            $errors += $batch.Count

            # Rate limited - wait and retry
            if ($result.error -eq 29) {
                Write-Host "  Rate limited. Waiting 60s..." -ForegroundColor Yellow
                Start-Sleep -Seconds 60
                $i -= $BatchSize
                continue
            }
        } else {
            $acc = [int]$result.scrobbles.'@attr'.accepted
            $ign = [int]$result.scrobbles.'@attr'.ignored
            $accepted += $acc
            $ignored += $ign
            $sent += $batch.Count

            if ($ign -gt 0) {
                $scrobbles = @($result.scrobbles.scrobble)
                $sample = $scrobbles | Where-Object { $_.ignoredMessage.code -ne '0' } | Select-Object -First 1
                if ($sample) {
                    $responseArtist = $sample.artist.'#text'
                    Write-Host "    Ignored - code $($sample.ignoredMessage.code) | last.fm saw artist: '$responseArtist'" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  NETWORK ERROR batch ${batchNum}: $_" -ForegroundColor Red
        Write-Host "  Retrying in 10s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        $i -= $BatchSize
        continue
    }

    # Progress
    $pct = [Math]::Round(($end / $total) * 100)
    Write-Host "  [$pct%] $end / $total  (accepted: $accepted, ignored: $ignored)" -ForegroundColor Gray

    if ($end -lt $total) { Start-Sleep -Milliseconds $DelayMs }
}

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "Sent: $sent | Accepted: $accepted | Ignored: $ignored | Errors: $errors"

# Move completed file to Uploaded folder
if ($accepted -gt 0) {
    if (-not (Test-Path $doneDir)) { New-Item -ItemType Directory -Path $doneDir | Out-Null }
    $fileName = [System.IO.Path]::GetFileName($filePath)
    Move-Item -Path $filePath -Destination (Join-Path $doneDir $fileName)
    Write-Host "Moved $fileName -> Uploaded\" -ForegroundColor Cyan
}
