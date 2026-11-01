# Releasing

`.github/workflows/release.yml` tests the package, builds a universal `MacOptimized.app`, packs it in
`MacOptimized-<version>.dmg` and publishes a GitHub release with the DMG and its SHA-256.

When the signing secrets below are set, the app and the DMG are signed with the **Developer ID
Application** certificate of team `RQTYDUV329` (hardened runtime, secure timestamp), notarized by Apple
and stapled, so the download opens on any Mac without a Gatekeeper warning. Without them the release
still succeeds, ad-hoc signed as before, with an *Unsigned macOS build* warning on the run and a note
in the release telling users to right-click › Open. Setting only some of the five secrets fails the run,
so a half-configured repository never publishes an unsigned build by accident.

## Cutting a release

1. Make sure `main` is green and contains what you want to ship.
2. Either push a tag:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

   or go to Actions › release › **Run workflow** and type the version without the `v` (`0.1.0`); the
   tag is created on the selected commit when the release is published. Tick **dry run** to only build,
   sign, notarize and test; the DMG is then kept as a workflow artifact and nothing is published.
3. The workflow:
   1. runs `swift test`;
   2. builds the universal app (`scripts/build-app.sh`), signed with the Developer ID identity;
   3. zips it, notarizes it with `xcrun notarytool submit --key … --wait` (`scripts/notarize.sh`) and
      staples the ticket to the app;
   4. packs the stapled app into the DMG (`scripts/make-dmg.sh`), signs, notarizes and staples the DMG;
   5. checks `codesign --verify --deep --strict`, the team ID, hardened runtime and timestamp, and
      `spctl --assess` on the app, on the DMG and on the app inside the mounted DMG;
   6. publishes the release.

   Notarization usually takes a few minutes per submission (there are two). If Apple rejects a
   submission, the step prints the notary log and the run fails before anything is published.
4. Check the release page, download the DMG on another Mac and open it: there should be no warning.

## One-time setup: repository secrets

Settings › Secrets and variables › Actions › **New repository secret**. The same five secrets are
used by the owner's other repositories, so they can also be set once as organization or account-wide
secrets and shared.

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | base64 of the exported Developer ID Application certificate and private key (`.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | the password chosen when exporting the `.p12` |
| `NOTARY_KEY_P8_BASE64` | base64 of the App Store Connect API key (`.p8`) |
| `NOTARY_KEY_ID` | the Key ID of that API key |
| `NOTARY_ISSUER_ID` | the Issuer ID shown above the keys list in App Store Connect |

### Signing certificate (`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`)

The certificate Xcode manages in the cloud can't be exported, so create one with a local private key
(an individual account can hold a limited number of Developer ID certificates; reuse an existing
exportable one if you have it):

1. Xcode › Settings › Accounts › select the team (`RQTYDUV329`) › **Manage Certificates…** › **+** ›
   **Developer ID Application**.
2. Keychain Access › login › My Certificates › right-click
   **Developer ID Application: YURI ALVES MIGUEL (RQTYDUV329)** (with its private key) › **Export…** ›
   save as `developer-id.p12` with a strong password.
3. Add the secrets:

   ```sh
   base64 -i developer-id.p12 | pbcopy   # paste as DEVELOPER_ID_P12_BASE64
   ```

   and the export password as `DEVELOPER_ID_P12_PASSWORD`.
4. Delete `developer-id.p12` from disk.

### Notarization API key (`NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`)

1. [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) › Users and Access ›
   Integrations › App Store Connect API › Team Keys › **+**, access **Developer**.
2. Download the `.p8` (possible only once) and note the **Key ID** and the **Issuer ID** above the list.
3. Add the secrets:

   ```sh
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # paste as NOTARY_KEY_P8_BASE64
   ```

   plus `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`.
4. Delete the `.p8` from disk. Revoke the key in App Store Connect if it ever leaks.

After adding the secrets, run the workflow once with **dry run** ticked to confirm signing and
notarization pass before tagging a real release.

## Entitlements

None. Under the hardened runtime the app needs no exception: it uses no JIT or executable memory, loads
only Apple-signed system frameworks, and its only scripting is `osascript` running `do shell script …
with administrator privileges`, which sends no Apple Events to other apps. Full Disk Access is a
privacy permission the user grants in System Settings, not an entitlement. If a future feature needs
one (for example Apple Events to another app), add an `.entitlements` file and pass
`--entitlements` to the `codesign` call in `scripts/build-app.sh`.

## Signing and notarizing from a Mac

The scripts work locally with a Developer ID certificate in the login keychain:

```sh
export CODESIGN_IDENTITY="Developer ID Application"
VERSION=0.1.0 UNIVERSAL=1 ./scripts/build-app.sh

xcrun notarytool store-credentials macoptimized   # once; Apple ID + app-specific password, or the API key
export NOTARY_KEYCHAIN_PROFILE=macoptimized
ditto -c -k --keepParent build/MacOptimized.app build/MacOptimized.zip
./scripts/notarize.sh build/MacOptimized.zip && xcrun stapler staple build/MacOptimized.app

SKIP_APP_BUILD=1 ./scripts/make-dmg.sh
./scripts/notarize.sh build/MacOptimized-0.1.0.dmg && xcrun stapler staple build/MacOptimized-0.1.0.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 build/MacOptimized-0.1.0.dmg
```

Without `CODESIGN_IDENTITY` the scripts ad-hoc sign, as they always have.
