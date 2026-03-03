# Developer ID Application Setup

ShipHook is intended to build and publish Sparkle releases for macOS apps distributed outside the Mac App Store.

For that workflow, the certificate you want is:

`Developer ID Application`

Do not use these for Sparkle release archives:

- `Apple Development`
- `Mac Development`
- `Apple Distribution`
- `Mac App Distribution`
- `Developer ID Installer` (this is for `.pkg` installers, not the app itself)

## Create the certificate

1. Open `Keychain Access`.
2. Choose `Keychain Access` > `Certificate Assistant` > `Request a Certificate From a Certificate Authority...`.
3. Enter your email address and common name.
4. Choose `Saved to disk`.
5. Save the `.certSigningRequest` file.
6. Go to [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list).
7. Create a new certificate.
8. Choose `Developer ID Application`.
9. Choose `G2 Sub-CA (Xcode 11.4.1 or later)`.
10. Upload the `.certSigningRequest` file created on this Mac.
11. Download the issued certificate.

## Import the certificate

1. Double-click the downloaded certificate file to import it into Keychain Access.
2. Open `Keychain Access` and look under `My Certificates`.
3. Confirm you can see:

   `Developer ID Application: Your Name (TEAMID)`

4. Confirm there is a private key nested under that certificate.

If the certificate appears without a private key, the import is incomplete and `xcodebuild` will not be able to sign with it.

## Verify from Terminal

ShipHook and `xcodebuild` depend on command-line keychain access, so verify with:

```sh
security find-identity -v -p codesigning
```

You want to see something like:

```text
Developer ID Application: Your Name (TEAMID)
```

If the command says `0 valid identities found`, then the certificate is not usable yet by command-line tools.

## Common problems

### The certificate is visible in Keychain Access but not in `security find-identity`

Usually one of these is true:

- the private key is missing
- the certificate was created from a CSR on another machine
- the identity was imported incorrectly
- the keychain/key access is not available to command-line tools

### Xcode Organizer works but ShipHook does not

That usually means Xcode GUI can access the signing material, but command-line tools cannot. ShipHook uses `xcodebuild`, so the Terminal check above is the authoritative test.

## ShipHook settings

For Sparkle release archives, prefer:

- `Code Sign Style`: `Manual`
- `Code Sign Identity`: `Developer ID Application: Your Name (TEAMID)`
- `Development Team`: your Apple team ID

After signing, a real Sparkle release flow should also notarize and staple the app before publishing.
