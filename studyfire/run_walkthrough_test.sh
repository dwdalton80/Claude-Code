#!/bin/bash
# Test script for the first-launch walkthrough
# Run from the studyfire project root

cd "$(dirname "$0")"

# Optional: clear walkthrough prefs so it shows fresh every time
flutter run --dart-define=RESET_WALKTHROUGH=true "$@"
