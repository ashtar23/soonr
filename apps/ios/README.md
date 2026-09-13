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

## Configurations

`Configurations/` holds one `.xcconfig` per build configuration, feeding
`Configurations/Info.plist`, which the app reads at runtime:

| Configuration | Backend |
| --- | --- |
| `Debug` | staging, overridable from the Xcode scheme |
| `Staging` | staging, optimized build for distribution |
| `Release` | production; `SOONR_API_HOST` is empty until the production API exists, so a Release build fails fast instead of silently using staging |

Values that must not be committed belong in `Configurations/Local.xcconfig`,
which is gitignored; copy `Local.xcconfig.example` to start. This mirrors how
`apps/mobile` keeps its `.env` files out of git.

Debug builds still accept an Xcode scheme override:

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

`-scheme` is required rather than `-target`: only a scheme build resolves and
builds Swift package dependencies.

```sh
xcodebuild \
  -project apps/ios/Soonr.xcodeproj \
  -scheme Soonr \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project apps/ios/Soonr.xcodeproj \
  -scheme Soonr \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  test
```

**Do not install a `CODE_SIGNING_ALLOWED=NO` build to try the app.** It is fine
for checking that the code compiles, which is all CI uses it for, but the
resulting app has no Keychain entitlement. Supabase stores the session in the
Keychain, so signing in appears to work while nothing is saved: every
authenticated request then goes out with no token and comes back 401, and the
session is gone on the next launch. Build without that flag before installing
to a simulator, or run from Xcode.

### Snapshot tests

`SoonrTests/Support/ViewSnapshot.swift` renders design-system views with
`ImageRenderer` and compares them with PNG references committed in
`__Snapshots__` beside each test. They exist because unit tests cannot see
layout: a row whose artwork overflowed its frame once shipped past a green
suite.

References are valid on one iOS major version and in `en_US`, because release
dates are formatted through the current locale. The suites skip themselves
anywhere else, so the iOS 17 run above stays green.

`ImageRenderer` renders SwiftUI content only. A `List` comes out as the
unsupported-view placeholder and a `ScrollView` comes out blank, so a screen
built from either is split, and the snapshot covers the content view inside
it. Give that view a generous frame: too short a one makes SwiftUI truncate
text, recording a layout bug the scrolling screen does not have. Artwork is
absent by design, since `AsyncImage` cannot load during a render.

After a deliberate design change, re-record and review the result before
committing it:

```sh
TEST_RUNNER_SOONR_RECORD_SNAPSHOTS=1 xcodebuild \
  -project apps/ios/Soonr.xcodeproj \
  -scheme Soonr \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:SoonrTests/TitleRowSnapshotTests \
  test
```

Recording always fails the run, so a branch left in recording mode cannot pass
CI. When a comparison fails, the rendered output is written next to the
reference as `<name>.actual.png` for side-by-side inspection; it is gitignored.

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
- Email and password sign-in through Supabase, with session restore and sign out
- Authenticated requests to `apps/api`
- Skeleton account creation and settings routes
- Swift Testing coverage for tabs, search and details models, API requests,
  response decoding, and release-date formatting

Deferred:

- Remaining API endpoints and Supabase authentication
- Authentication state
- Watchlist and notification persistence
- Production assets, signing, and release configuration
