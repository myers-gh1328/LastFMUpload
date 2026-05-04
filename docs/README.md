# Spotify to Last.fm Scrobbler

A small PowerShell utility for importing Spotify or Apple Music listening history into Last.fm.

The tool prepares local listening-history exports, then sends prepared tracks to Last.fm in batches using the `track.scrobble` API.

## Requirements

- PowerShell 7+
- A Last.fm account
- A Last.fm API application
- Spotify Extended Streaming History JSON files or Apple Music play activity CSV files

Install PowerShell:

https://learn.microsoft.com/powershell/scripting/install/installing-powershell

Create a Last.fm API application here:

https://www.last.fm/api/account/create

Use `http://localhost` as the callback URL.

## Usage

Place raw Spotify or Apple Music export files in a `RawData` folder next to the scripts, then run the launcher.

Windows:

```text
Double-click Run-LastFM-Upload.cmd
```

macOS:

```bash
chmod +x Run-LastFM-Upload.command
open Run-LastFM-Upload.command
```

Linux:

```bash
chmod +x run-lastfm-upload.sh
./run-lastfm-upload.sh
```

The launcher checks whether prepared files already exist:

- If Last.fm setup has not been completed, it offers to run setup first.
- If prepared files exist, it offers to upload them or prepare new files.
- If no prepared files exist, it offers to prepare files from `RawData`.
- The menu also includes an option to update Last.fm setup later.

You can also run the PowerShell scripts directly:

```powershell
.\src\prepare-history.ps1
```

```powershell
.\src\scrobble.ps1
```

On first upload, the script walks you through Last.fm API setup and account authorization. After that, it lists available prepared JSON files and prompts you to choose one to upload.

Optional parameters:

```powershell
.\scrobble.ps1 -BatchSize 50 -DelayMs 1500
```

```powershell
.\scrobble.ps1 -Debug
```

## Getting Your Listening History

### Spotify

1. Log into Spotify in a web browser.
2. Go to Account Settings > Privacy Settings.
3. Scroll to Download your data.
4. Request Extended Streaming History.
5. Confirm the request from the email Spotify sends you.
6. Wait for Spotify to prepare the data. This can take up to 30 days.
7. Download the ZIP file from Spotify's email.
8. Extract the JSON files, such as `endsong_0.json`.

### Apple Music

1. Go to https://privacy.apple.com.
2. Sign in with your Apple ID.
3. Select Request a copy of your data.
4. Select Apple Media Services information.
5. Wait for Apple to prepare the data. This usually takes 3 to 7 days.
6. Download the data from Apple's email.
7. Find the listening history CSV in the Apple Music Activity folder. The file is usually named `Apple Music Play Activity.csv`.

## Raw Input Format

The preparation script accepts:

- Spotify `.json` files from Extended Streaming History, such as `endsong_0.json`
- Apple Music `.csv` files, such as `Apple Music Play Activity.csv`

See:

- [examples/sample-spotify-extended-history.json](examples/sample-spotify-extended-history.json)
- [examples/sample-apple-music-play-activity.csv](examples/sample-apple-music-play-activity.csv)

## Prepared Format

Prepared files are written to `ExportedData` as JSON arrays:

```json
[
  {
    "artistName": "Example Artist",
    "albumName": "Example Album",
    "trackName": "Example Track",
    "time": "2024-01-15T18:30:00Z"
  }
]
```

See [examples/sample-export.json](examples/sample-export.json) for a small fake prepared dataset.

## Behavior

- Raw files are converted locally.
- Plays shorter than 30 seconds are skipped.
- Rows missing artist, track, or time are skipped.
- Prepared tracks are sorted oldest-first.
- Prepared tracks are split into JSON files.
- Prepared tracks are sent to Last.fm in batches.
- Uploaded scrobbles are timestamped relative to the current time.
- Completed files are moved from `ExportedData` to `Uploaded` after successful uploads.
- The script retries after transient network errors and handles Last.fm rate-limit responses.

## Notes

Last.fm may ignore some scrobbles depending on its own rules. The script reports accepted and ignored counts after each batch.

## License

MIT. See [LICENSE](LICENSE).
