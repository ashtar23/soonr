#!/bin/sh
# Fails when any Swift source deviates from .swift-format.
# Fix most findings with: apps/ios/Scripts/format.sh
set -eu

cd "$(dirname "$0")/.."

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "swift-format not found; skipping iOS lint (needs Xcode 16 or newer)."
    exit 0
fi

exec xcrun swift-format lint \
    --configuration .swift-format \
    --strict \
    --recursive \
    --parallel \
    Soonr SoonrTests
