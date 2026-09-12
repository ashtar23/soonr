# Soonr for iOS

Native SwiftUI rebuild of Soonr supporting iOS 17 and newer. The app uses
current platform capabilities where available, including native Liquid Glass
behavior on iOS 26, while retaining system-native fallbacks on earlier releases.
It currently contains the five documented primary tabs plus guest game search
backed by the Soonr API.

- [Architecture](ARCHITECTURE.md)
- [Vertical-slice roadmap](ROADMAP.md)

## Requirements

- Xcode 26 or newer
- A simulator runtime compatible with the selected Xcode version

The project uses synchronized folders: add a Swift file anywhere under `Soonr/`
or `SoonrTests/` and it joins that target automatically, with no project file
edit.

## Open and run

Open `Soonr.xcodeproj`, select the `Soonr` scheme, and run it on a simulator.
For compatibility checks, test the oldest supported iOS 17 runtime and the
latest available iOS runtime.

The app uses `https://soonr-staging.up.railway.app` by default. Override it in
the Xcode scheme when needed:

```text
SOONR_API_BASE_URL=http://127.0.0.1:3001
SOONR_SUPABASE_PUBLISHABLE_KEY=<optional publishable key>
```

## Formatting and lint

Swift sources are formatted with `swift-format`, which ships with Xcode, using
the settings in `.swift-format`. No install step is needed.

```sh
apps/ios/Scripts/format.sh   # format in place
apps/ios/Scripts/lint.sh     # fail on any deviation
```

`Scripts/lint.sh` also runs in the repository pre-push hook, and skips itself
with a message on machines without Xcode.

Command-line verification:

```sh
xcodebuild \
  -project apps/ios/Soonr.xcodeproj \
  -target Soonr \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project apps/ios/Soonr.xcodeproj \
  -scheme Soonr \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  test
```

## Continuous integration

`.github/workflows/ios-ci.yml` runs lint, the iOS 17 deployment build, and the
test suite on every pull request and on `dev` and `main`, but only when
`apps/ios` changes, because macOS runner minutes are billed at a premium.

GitHub's macOS images carry iOS 26 simulator runtimes only. CI therefore proves
the app still compiles against the iOS 17 deployment target, while running the
suite on iOS 26. Running the tests on an iOS 17 runtime, and any UI check of
compatibility-sensitive behavior, stays a local step:

```sh
xcodebuild \
  -project apps/ios/Soonr.xcodeproj \
  -scheme Soonr \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' \
  test
```

## Scope

Included:

- Swift 6 and SwiftUI
- iOS 17 deployment target
- Modern tab APIs on iOS 18 and native Liquid Glass behavior on iOS 26
- System-native tab and control fallbacks on earlier supported releases
- Home, Watchlist, Notifications, Search, and Account tabs
- Home discovery rails from `/home/discovery` with pull to refresh
- Debounced guest title search with loading, empty, error, and result states
- Title details from search results with loading, not-found, error, and retry
  states
- Skeleton authentication and settings routes
- Swift Testing coverage for tabs, search and details models, API requests,
  response decoding, and release-date formatting

Deferred:

- Remaining API endpoints and Supabase authentication
- Authentication state
- Watchlist and notification persistence
- Production assets, signing, and release configuration
