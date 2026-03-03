# ShipHook

ShipHook is a macOS menu bar agent that polls GitHub branches for new commits, syncs a local checkout, runs a build pipeline, and then publishes a Sparkle-compatible update feed and GitHub release asset.

## What is included

- `ShipHook.xcodeproj`: native macOS app project
- `ShipHook/Sources`: SwiftUI menu bar agent, GitHub polling, build orchestration, and shell execution
- `publish_sparkle_release.sh`: generic Sparkle/appcast publisher for any repo/app
- `ShipHook/Resources/SampleConfig.json`: starter config copied into `~/Library/Application Support/ShipHook/config.json` on first launch

## How the agent works

1. Poll GitHub's branch endpoint for each configured repository.
2. When the latest SHA changes, fetch and checkout that commit in the configured local checkout.
3. Build either with `xcodebuild archive/exportArchive` or a custom shell command.
4. Run the configured publish command, usually `publish_sparkle_release.sh`.
5. Surface status and logs in the app UI.

## Configuration

On first launch, ShipHook writes a sample config to:

`~/Library/Application Support/ShipHook/config.json`

Each repository entry supports:

- GitHub owner, repo, branch
- local checkout path to build from
- `xcodeArchive` mode for standard Xcode archive/export workflows
- `shell` mode for custom build pipelines
- a publish command that receives these environment variables:

`SHIPHOOK_WORKSPACE_ROOT`, `SHIPHOOK_REPO_ID`, `SHIPHOOK_REPO_NAME`, `SHIPHOOK_GITHUB_OWNER`, `SHIPHOOK_GITHUB_REPO`, `SHIPHOOK_BRANCH`, `SHIPHOOK_SHA`, `SHIPHOOK_SHORT_SHA`, `SHIPHOOK_VERSION`, `SHIPHOOK_LOCAL_CHECKOUT_PATH`, `SHIPHOOK_RELEASE_NOTES_PATH`, `SHIPHOOK_ARTIFACT_PATH`, `SHIPHOOK_BUNDLED_PUBLISH_SCRIPT`

## Example publish command

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

## Build

```sh
xcodebuild -project ShipHook.xcodeproj -scheme ShipHook -configuration Debug build
```

The project currently disables code signing so it can be built locally before you wire in your own signing setup.
