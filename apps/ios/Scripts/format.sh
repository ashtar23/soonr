#!/bin/sh
# Formats every Swift source in place using .swift-format.
set -eu

cd "$(dirname "$0")/.."

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "swift-format not found; install Xcode 16 or newer." >&2
    exit 1
fi

exec xcrun swift-format format \
    --configuration .swift-format \
    --in-place \
    --recursive \
    --parallel \
    Soonr SoonrTests
