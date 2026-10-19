# Offline download progress evidence

Captured at a 390 × 844 CSS-pixel phone viewport (device pixel ratio 2).
These are browser screenshots of the actual Flutter `OfflineMapScreen`, supplied
with a deterministic service snapshot: 12.4 MB saved, 123 of 456 files completed.
They demonstrate the UI states, rather than a live device download. On the web,
the normal app reports offline storage as unsupported.

- [Before](before.png): the screen from commit `2d0c9c5`, showing files and 27%.
- [Downloading](downloading.png): MB downloaded, an indeterminate bar, and Pause.
- [Paused](paused.png): saved MB, a still bar, and Resume/Delete.

The backend and tile host do not provide a reliable full-pack byte total, so the
UI shows downloaded MB without estimating a denominator. Values retain the
app's existing 1024 × 1024 conversion and always use one decimal place.

Behavior is verified separately by `flutter test test/features/offline`:
streamed bytes are visible before a file is saved, successful transfers are
counted once, failed partial transfers are discarded, and resuming retains
saved bytes and skips stored files. Widget tests verify the MB labels and bar
states.
