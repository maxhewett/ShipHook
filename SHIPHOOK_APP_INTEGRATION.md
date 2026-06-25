# ShipHook App Integration Guide

This guide is for app developers whose macOS apps are built and published by ShipHook.

## Repository Requirements

- The app must live in a GitHub repository that ShipHook can clone and pull.
- The release branch should be stable and predictable, usually `main`.
- Appcast commits made by ShipHook include `[shiphook skip]`; do not remove that marker from generated appcast commits.
- Keep `CFBundleShortVersionString` and `CFBundleVersion` valid for Sparkle. Build versions must be numeric, or beta-prefixed numeric when ShipHook is publishing a beta channel.

## Sparkle Requirements

Your app should use Sparkle 2 and include the normal Sparkle appcast configuration in its app bundle.

At minimum, the app should have:

- `SUFeedURL` pointing to the appcast ShipHook publishes.
- `SUPublicEDKey` matching the private key used by Sparkle's `generate_appcast`.
- A working `SPUStandardUpdaterController` or equivalent Sparkle updater integration.
- Release archives signed with a `Developer ID Application` identity and notarized before publishing.

ShipHook publishes stable appcasts to:

```text
docs/appcast.xml
```

Beta releases publish to:

```text
docs/beta/appcast.xml
```

## What's New Window

Sparkle shows its What's New window from the release notes linked in the appcast. ShipHook keeps this compatible by publishing an HTML release notes page and setting Sparkle's release notes link in `appcast.xml`.

For generated notes, ShipHook writes the commit title/body into a small HTML page. If your project provides its own versioned release notes file, enable `Use existing versioned release notes file when present` in ShipHook and place files at:

```text
docs/release-notes/<version>.html
docs/beta/release-notes/<version>.html
```

Use complete HTML pages or simple HTML fragments that Sparkle can display cleanly. Keep them lightweight; avoid remote scripts, tracking pixels, or content that depends on a logged-in browser session.

## GitHub Release Notes

GitHub releases should use Markdown or plain text, not the full Sparkle HTML page. ShipHook's bundled publish script converts HTML release-note documents into a plain Markdown-style body before calling `gh release create`.

If you want full control over the GitHub release body, pass a Markdown file to the publish script:

```sh
bash "$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT" \
  --version "$SHIPHOOK_VERSION" \
  --artifact "$SHIPHOOK_ARTIFACT_PATH" \
  --github-release-notes ./RELEASE_NOTES.md \
  --release-notes "$SHIPHOOK_RELEASE_NOTES_PATH"
```

The `--release-notes` file remains the Sparkle/What's New HTML page.

## Automated vs Manual Releases

ShipHook supports two release modes per repository:

- Automated: ShipHook checks the repository on the background polling interval and builds new commits.
- Manual: ShipHook does not build from the background polling loop. Use `Check Now` in the app, webUI, or API to inspect and release the repository on demand.

Manual mode is useful for apps where the branch receives many ordinary commits, but only selected commits should become releases.

## Delta Updates

ShipHook can request Sparkle delta update generation when the installed `generate_appcast` tool supports delta generation.

To make delta updates work reliably:

- Use Sparkle 2 in the app.
- Keep previous release archives available in the repository's configured `release-artifacts` directory.
- Do not rename archived apps between releases unless the app bundle name also changed intentionally.
- Keep signing and notarization consistent between releases.
- Ensure `SPARKLE_GENERATE_APPCAST` points to a Sparkle tool version that supports delta generation if Xcode's DerivedData lookup cannot find it.

Enable `Generate Sparkle delta updates when supported` in the repository's Sparkle settings. ShipHook sets:

```text
SHIPHOOK_SPARKLE_DELTA_UPDATES=1
```

for the publish command. If the local Sparkle tool does not support delta generation, ShipHook logs that and continues publishing a normal full update.

## Recommended Release Notes Workflow

For small projects, generated commit notes are fine.

For public releases, prefer versioned HTML release notes:

```text
docs/release-notes/1.4.html
```

Then enable `Use existing versioned release notes file when present` in ShipHook. This avoids turning incidental commit messages like `chore: update readme` into user-facing release notes.

