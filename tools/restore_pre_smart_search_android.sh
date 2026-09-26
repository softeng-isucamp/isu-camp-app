#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apk="$repo_root/.scratch/pre-smart-search-test.apk"
expected_sha256="7abf47d08d78a7adbad315b307c5e5c6b3446eb94bb54794ab2e4da4762e43a0"

if [[ ! -f "$apk" ]]; then
  echo "Backup APK is missing: $apk" >&2
  exit 1
fi
actual_sha256="$(sha256sum "$apk" | cut -d' ' -f1)"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Backup APK checksum does not match the recorded pre-test build." >&2
  exit 1
fi

adb install -r "$apk"
echo "Restored the pre-smart-search app build without clearing app data."
