$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "src/prepare-history.ps1"
$sandbox = Join-Path $PSScriptRoot "tmp-prepare-history"
$rawDir = Join-Path $sandbox "RawData"
$outDir = Join-Path $sandbox "ExportedData"

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

if (Test-Path $sandbox) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}

New-Item -ItemType Directory -Path $rawDir | Out-Null

@(
    @{
        master_metadata_album_artist_name = "Spotify Artist"
        master_metadata_album_album_name = "Spotify Album"
        master_metadata_track_name = "Spotify Track"
        ts = "2024-01-02T10:00:00Z"
        ms_played = 45000
    },
    @{
        master_metadata_album_artist_name = "Too Short"
        master_metadata_album_album_name = "Short Album"
        master_metadata_track_name = "Short Track"
        ts = "2024-01-02T10:01:00Z"
        ms_played = 12000
    },
    @{
        master_metadata_album_artist_name = ""
        master_metadata_album_album_name = "Missing Album"
        master_metadata_track_name = "Missing Artist Track"
        ts = "2024-01-02T10:02:00Z"
        ms_played = 50000
    }
) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $rawDir "endsong_0.json") -Encoding UTF8

@'
Artist Name,Content Name,Event Start Timestamp,Play Duration Milliseconds
Apple Artist,Apple Track,2024-01-01T09:00:00Z,60000
Short Apple,Short Track,2024-01-01T09:01:00Z,5000
,Missing Artist Apple,2024-01-01T09:02:00Z,50000
'@ | Set-Content -Path (Join-Path $rawDir "Apple Music Play Activity.csv") -Encoding UTF8

& $scriptPath -InputDirectory $rawDir -OutputDirectory $outDir -ChunkSize 2

$files = Get-ChildItem -Path $outDir -Filter "*.json" | Sort-Object Name
Assert-Equal 1 $files.Count "Prepared file count mismatch."

$tracks = Get-Content -Raw $files[0].FullName | ConvertFrom-Json
Assert-Equal 2 $tracks.Count "Prepared track count mismatch."
Assert-Equal "Apple Artist" $tracks[0].artistName "Tracks should be sorted oldest-first."
Assert-Equal "Apple Track" $tracks[0].trackName "Apple track name was not mapped."
Assert-Equal "Spotify Artist" $tracks[1].artistName "Spotify artist was not mapped."
Assert-Equal "Spotify Album" $tracks[1].albumName "Spotify album was not mapped."

Remove-Item -LiteralPath $sandbox -Recurse -Force
Write-Host "prepare-history tests passed"
