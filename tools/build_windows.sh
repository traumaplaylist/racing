#!/usr/bin/env bash
# Reproducible Windows export for Canyon Clash v0.1.
# Requires Godot 4.5.1-stable on PATH as `godot` (or GODOT=/path/to/godot) and the
# matching export templates in ~/.local/share/godot/export_templates/4.5.1.stable/
# (Windows: %APPDATA%\Godot\export_templates\4.5.1.stable\).
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

"$GODOT" --version | grep -q '^4\.5\.1\.stable' || { echo "Need Godot 4.5.1-stable"; exit 1; }
"$GODOT" --headless --import
"$GODOT" --headless res://tests/sim_test.tscn          # exit code = failed checks
mkdir -p build/windows
"$GODOT" --headless --export-release "Windows Desktop" build/windows/CanyonClash.exe
cp docs/PLAY.txt build/windows/PLAY.txt
rm -f build/CanyonClash-v0.1-windows-x86_64.zip
(cd build/windows && zip -9 -q ../CanyonClash-v0.1-windows-x86_64.zip CanyonClash.exe PLAY.txt)
ls -la build/CanyonClash-v0.1-windows-x86_64.zip
