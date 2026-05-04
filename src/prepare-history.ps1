param(
    [string]$InputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "RawData"),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "ExportedData"),
    [int]$ChunkSize = 2600
)

$ErrorActionPreference = "Stop"

function ConvertTo-StreamDate([object]$Value) {
    if (-not $Value) { return $null }

    $text = [string]$Value
    try {
        return ([DateTimeOffset]::Parse($text)).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
    } catch {
        return $null
    }
}

function New-StreamRecord([string]$ArtistName, [string]$AlbumName, [string]$TrackName, [object]$Time, [object]$Duration) {
    $durationMs = 0
    [void][double]::TryParse([string]$Duration, [ref]$durationMs)

    [pscustomobject]@{
        artistName = $ArtistName
        albumName = $AlbumName
        trackName = $TrackName
        time = ConvertTo-StreamDate $Time
        duration = $durationMs
    }
}

function Read-SpotifyJson([string]$Path) {
    $rows = @(Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json)
    foreach ($row in $rows) {
        New-StreamRecord `
            -ArtistName ($row.master_metadata_album_artist_name ?? $row.artistName) `
            -AlbumName ($row.master_metadata_album_album_name ?? $row.albumName) `
            -TrackName ($row.master_metadata_track_name ?? $row.trackName) `
            -Time ($row.ts ?? $row.endTime ?? $row.time) `
            -Duration ($row.ms_played ?? $row.msPlayed)
    }
}

function Read-AppleCsv([string]$Path) {
    $rows = @(Import-Csv -Path $Path)
    foreach ($row in $rows) {
        New-StreamRecord `
            -ArtistName $row.'Artist Name' `
            -AlbumName $row.'Album Name' `
            -TrackName ($row.'Content Name' ?? $row.'Song Name') `
            -Time $row.'Event Start Timestamp' `
            -Duration $row.'Play Duration Milliseconds'
    }
}

function Split-Array([array]$Items, [int]$Size) {
    for ($i = 0; $i -lt $Items.Count; $i += $Size) {
        $end = [Math]::Min($i + $Size - 1, $Items.Count - 1)
        ,@($Items[$i..$end])
    }
}

if ($ChunkSize -lt 1) {
    throw "ChunkSize must be at least 1."
}

if (-not (Test-Path $InputDirectory)) {
    New-Item -ItemType Directory -Path $InputDirectory | Out-Null
    Write-Host "Created RawData folder: $InputDirectory"
    Write-Host "Add Spotify JSON or Apple Music CSV files there, then run prepare again."
    exit 0
}

$files = @(Get-ChildItem -Path $InputDirectory -File | Where-Object {
    $_.Extension -in @(".json", ".csv")
})

if ($files.Count -eq 0) {
    Write-Host "No JSON or CSV files found in: $InputDirectory"
    exit 0
}

$allStreams = @()
$jsonFiles = 0
$csvFiles = 0

foreach ($file in $files) {
    switch ($file.Extension.ToLowerInvariant()) {
        ".json" {
            $jsonFiles++
            $allStreams += @(Read-SpotifyJson $file.FullName)
        }
        ".csv" {
            $csvFiles++
            $allStreams += @(Read-AppleCsv $file.FullName)
        }
    }
}

$originalCount = $allStreams.Count
$longEnough = @($allStreams | Where-Object { $_.duration -ge 30000 })
$shortCount = $originalCount - $longEnough.Count
$valid = @($longEnough | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.artistName) -and
    -not [string]::IsNullOrWhiteSpace($_.trackName) -and
    -not [string]::IsNullOrWhiteSpace($_.time)
})
$missingCount = $longEnough.Count - $valid.Count
$prepared = @($valid | Sort-Object { [DateTime]::Parse($_.time) } | ForEach-Object {
    [pscustomobject]@{
        artistName = $_.artistName
        albumName = $_.albumName
        trackName = $_.trackName
        time = $_.time
    }
})

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$existing = @(Get-ChildItem -Path $OutputDirectory -Filter "*.json" -File -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    Write-Host "Prepared JSON files already exist in: $OutputDirectory"
    $answer = Read-Host "Delete them before writing new prepared files? (y/N)"
    if ($answer -match '^(y|yes)$') {
        Remove-Item -LiteralPath $existing.FullName -Force
    }
}

if ($prepared.Count -eq 0) {
    Write-Host "No playable tracks found."
    exit 0
}

$chunks = @(Split-Array $prepared $ChunkSize)
for ($i = 0; $i -lt $chunks.Count; $i++) {
    $chunk = @($chunks[$i])
    $firstTime = [DateTimeOffset]::Parse($chunk[0].time).UtcDateTime.ToString("yyyy-MM-ddTHHmmssZ")
    $path = Join-Path $OutputDirectory $firstTime".json"
    $chunk | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
}

Write-Host "Found $originalCount streams from $jsonFiles JSON file(s) and $csvFiles CSV file(s)."
if ($shortCount -gt 0) { Write-Host "Removed $shortCount play(s) shorter than 30 seconds." }
if ($missingCount -gt 0) { Write-Host "Removed $missingCount play(s) missing artist, track, or time." }
Write-Host "Prepared $($prepared.Count) track(s) in $($chunks.Count) file(s)."
