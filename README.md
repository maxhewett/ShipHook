<img width="150" height="auto" alt="ShipHook" src="https://github.com/user-attachments/assets/fa580c86-0523-4f2c-a59c-383469e47f00" />

# ShipHook

ShipHook is a native macOS app and menu bar companion for monitoring GitHub repositories, detecting new pushes, building release archives, and publishing Sparkle appcasts and release artifacts.

<img width="1232" height="884" alt="shpreview" src="https://github.com/user-attachments/assets/2c64a5ea-e7a7-4335-be06-0981b829daf6" />


## Current Status

- Native macOS app in [`ShipHook.xcodeproj`](/Users/max/Developer/ShipHook/ShipHook.xcodeproj)
- Multi-repo dashboard with guided repo setup
- GitHub polling with per-repo queueing and live logs
- Xcode archive and custom shell build pipelines
- Sparkle release planning against the latest appcast item
- Signing diagnostics and signing override support
- Generic Sparkle/appcast publisher in [`publish_sparkle_release.sh`](/Users/max/Developer/ShipHook/publish_sparkle_release.sh)
- Sparkle self-update entry point for ShipHook itself

## Project Layout

- [`ShipHook.xcodeproj`](/Users/max/Developer/ShipHook/ShipHook.xcodeproj): app target and Xcode package configuration
- [`ShipHook/Sources`](/Users/max/Developer/ShipHook/ShipHook/Sources): SwiftUI app, polling, orchestration, Sparkle updater, and shell execution
- [`ShipHook/Resources/SampleConfig.json`](/Users/max/Developer/ShipHook/ShipHook/Resources/SampleConfig.json): starter config copied to Application Support on first launch
- [`publish_sparkle_release.sh`](/Users/max/Developer/ShipHook/publish_sparkle_release.sh): reusable Sparkle/appcast publishing script
- [`DEVELOPER_ID_SETUP.md`](/Users/max/Developer/ShipHook/DEVELOPER_ID_SETUP.md): how to create and install a `Developer ID Application` certificate

## What ShipHook Automates

1. Poll GitHub for new commits on configured branches.
2. Ignore ShipHook-managed appcast commits marked with `[shiphook skip]`.
3. Queue builds so only one repository pipeline runs at a time.
4. Sync the local checkout to the latest GitHub branch state without detaching `HEAD`.
5. Inspect the target project and plan the next Sparkle-safe build version.
6. Build using `xcodebuild archive` or a custom shell command.
7. Publish the release artifact, appcast, and optional appcast commit push.
8. Surface live pipeline phase, status, and log output in the app.

## Dashboard Features

- Multiple repositories in a single config
- Guided add-repository wizard
- Default appcast URL inference using `https://<owner>.github.io/<repo>/appcast.xml`
- Release build planning against the latest appcast item
- Local signing identity detection
- Per-repo signing overrides
- Live log tailing from `.shiphook/logs/<repo-id>-latest.log`
- Reset for stale in-progress build state
- Organizer-visible Xcode archive output

## Configuration

On first launch, ShipHook writes config to:

```text
~/Library/Application Support/ShipHook/config.json
```

You can manage that config from the ShipHook dashboard instead of editing JSON directly.

Each repository supports:

- GitHub owner, repo, branch
- local checkout path
- optional working directory and release notes path
- `xcodeArchive` build mode
- `shell` build mode
- per-repo environment values
- Sparkle appcast URL and auto-increment build behavior
- signing overrides for team, identity, and sign style
- a publish command fed by ShipHook environment variables

## Publish Environment

ShipHook injects these environment variables into publish commands:

```text
SHIPHOOK_WORKSPACE_ROOT
SHIPHOOK_REPO_ID
SHIPHOOK_REPO_NAME
SHIPHOOK_GITHUB_OWNER
SHIPHOOK_GITHUB_REPO
SHIPHOOK_BRANCH
SHIPHOOK_SHA
SHIPHOOK_SHORT_SHA
SHIPHOOK_VERSION
SHIPHOOK_LOCAL_CHECKOUT_PATH
SHIPHOOK_RELEASE_NOTES_PATH
SHIPHOOK_ARTIFACT_PATH
SHIPHOOK_APPCAST_URL
SHIPHOOK_BUNDLED_PUBLISH_SCRIPT
```

## Example Publish Command

```sh
bash "$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT" \
  --version "$SHIPHOOK_VERSION" \
  --artifact "$SHIPHOOK_ARTIFACT_PATH" \
  --app-name "ExampleApp" \
  --repo-owner "$SHIPHOOK_GITHUB_OWNER" \
  --repo-name "$SHIPHOOK_GITHUB_REPO" \
  --release-notes "$SHIPHOOK_RELEASE_NOTES_PATH" \
  --docs-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs" \
  --releases-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts" \
  --working-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH"
```

## Appcast Commit Loop Prevention

`publish_sparkle_release.sh` can commit and push `appcast.xml` updates back to the repo. Those commits are tagged like:

```text
chore(shiphook): update appcast for AppName 1.2.3 [shiphook skip]
```

ShipHook ignores commits containing `[shiphook skip]` or `[skip shiphook]`, which prevents infinite rebuild loops.

## Signing

For Sparkle-distributed macOS apps, ShipHook expects `Developer ID Application` signing for release archives.

Use:

- [`DEVELOPER_ID_SETUP.md`](/Users/max/Developer/ShipHook/DEVELOPER_ID_SETUP.md) to create and install the certificate
- the signing section in the dashboard to pick the local identity
- manual signing overrides when the target project does not already archive correctly on its own

## ShipHook Self-Updates

ShipHook itself now includes a Sparkle updater entry point using `SPUStandardUpdaterController`.

You can trigger it from:

- the app menu: `Check for Updates...`
- the menu bar extra: `Check for Updates...`

ShipHook currently ships with these Sparkle Info.plist-style build settings:

```text
SUFeedURL=https://maxhewett.github.io/ShipHook/appcast.xml
SUPublicEDKey=rxaJsfCpTKtpqRubSfkJwKnztT5S8RHsdAueuT+jKck=
SUEnableAutomaticChecks=YES
```

Important:

- ShipHook's own release feed must exist and be signed correctly for Sparkle to work

The updater implementation lives in:

- [`AppUpdater.swift`](/Users/max/Developer/ShipHook/ShipHook/Sources/AppUpdater.swift)

## Build

```sh
xcodebuild -project /Users/max/Developer/ShipHook/ShipHook.xcodeproj \
  -scheme ShipHook \
  -configuration Debug \
  -derivedDataPath /Users/max/Developer/ShipHook/.build-xcode \
  build
```

## Sparkle Integration Snippet

ShipHook now uses the same Sparkle pattern you would use in a normal SwiftUI app:

```swift
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
```

## Notes

- ShipHook archives target apps into Xcode's standard archives location so they appear in Organizer.
- Repo-local derived data is still used for build isolation and reliability.
- The app currently still emits a non-blocking warning for `NSWorkspace.icon(forFileType:)`; functionality is unaffected.
