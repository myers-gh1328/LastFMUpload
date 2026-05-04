#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell 7+ was not found."
  echo "Install it from https://learn.microsoft.com/powershell/scripting/install/installing-powershell"
  echo
  read -r -p "Press Enter to close..."
  exit 1
fi

pwsh -NoProfile -File "./src/Start-LastFM-Upload.ps1"

echo
read -r -p "Press Enter to close..."
