# TestFlight delivery

## Status and scope

The local pipeline is implemented in `.github/workflows/ios-testflight.yml`.
It has **not** been run on GitHub or uploaded to Apple. No credentials are
included, and no commit/push is part of preparation. The existing server
workflow is independent.

- Push to `main` changing `native/**` or this workflow: validate, then deploy.
- Manual **Actions → iOS TestFlight → Run workflow**, choosing `main`: same path.
- Pull requests: Python tests, Swift core tests, XcodeGen, unsigned Release
  simulator build only. No signing secrets, environment, or upload on PRs.
- Deployment requires the protected GitHub environment `testflight` and only
  runs from `refs/heads/main`. All workflow permissions are `contents: read`;
  checkout does not persist credentials. Concurrency serializes deployment,
  with `cancel-in-progress: false` (GitHub may replace an older *pending* run).
- Both jobs explicitly select `/Applications/Xcode_26.6.app/Contents/Developer`
  on `macos-26`, then log Xcode/Swift versions. Xcode 26.6 was listed as stable
  in the runner inventory when prepared. A missing version fails loudly; do
  not silently select a beta or assume the local Xcode 27.2 exists on runners.
  Update both job paths together when the image removes this version.

## Apple setup (account owner/admin)

1. Have an active paid Apple Developer Program membership, accept current
   developer/App Store Connect agreements, and use team **49PJNAT2WC**.
2. In Certificates, Identifiers & Profiles create/verify an **explicit** App ID
   **de.keinemagie.app**. Enable **Sign in with Apple**, configured as the
   primary app ID as appropriate. The app entitlement is `Default`. The server
   must trust this same Apple audience and validate real identity tokens.
3. Create an **Apple Distribution** certificate using a CSR from a controlled
   Mac. Export the certificate **with its private key** from Keychain Access
   to a password-protected `.p12`. A `.cer` without the private key cannot sign.
   Retain the password securely. Include exactly one distribution identity.
4. Create an **App Store Connect / App Store distribution** iOS provisioning
   profile for that explicit App ID and that distribution certificate.
   Regenerate/download it after enabling Sign in with Apple. Development,
   Ad Hoc, wildcard, and Enterprise profiles are rejected. No registered
   devices are required for TestFlight.
5. In App Store Connect create the iOS app record with bundle ID
   `de.keinemagie.app`, select its primary language, name, and a unique SKU.
   The record must exist before upload; the pipeline does not create it.
6. Under **Users and Access → Integrations → App Store Connect API**, request
   API access if necessary and create a **team API key** with the minimum role
   that can upload builds (Developer or App Manager, with access to this app).
   Download its `.p8` once; record its Key ID and Issuer ID. This is an **App
   Store Connect API key**, not a Sign in with Apple server key. Never paste
   private key contents into chat or logs.
7. Configure TestFlight test information, contact details, and internal tester
   group in App Store Connect. External testing needs beta review and may
   require additional metadata. A successful upload is not tester availability.

## GitHub configuration

Create environment **testflight**, restrict deployment branches to **main**,
add required reviewers where your GitHub plan supports them, and protect main
with review/required checks. Put these six secrets **in that environment**, not
in the repository, so PR validation cannot read them:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64 of the Apple Distribution `.p12` with private key |
| `P12_PASSWORD` | Export password of that `.p12` (nonempty) |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64 of the downloaded App Store `.mobileprovision` |
| `ASC_PRIVATE_KEY_BASE64` | Base64 of the App Store Connect `.p8` |
| `ASC_KEY_ID` | 10-character API key ID |
| `ASC_ISSUER_ID` | Issuer UUID |

On a trusted Mac, copy base64 to the clipboard without printing it:

```sh
base64 -i /secure/path/Distribution.p12 | pbcopy
base64 -i /secure/path/AppStore.mobileprovision | pbcopy
base64 -i /secure/path/AuthKey_KEYID.p8 | pbcopy
```

Paste each value into its matching environment secret; clear the clipboard
when finished. Never commit the source files, their base64, or passwords.
No personal Apple ID/password, app-specific password, persistent keychain
password, automatic provisioning credentials, or GitHub write token is used.
The temporary keychain password is generated per run and masked.

## Build, signing, and upload behavior

`native/ci/testflight.sh` runs only in Actions on main. It decodes credentials
under a mode-0700 unique runner-temp directory, checks the `.p8` privately,
extracts only the public certificate, and validates:

- current iOS App Store profile (no devices or all-devices flag,
  `get-task-allow=false`, `beta-reports-active=true`);
- exact team, bundle ID, Apple sign-in entitlement, profile UUID and validity;
- profile includes the actual imported certificate; certificate has Apple
  Distribution common name and exact team OU, is unexpired, and macOS reports
  a valid signing identity with its private key/chain.

`native/ci/signing_config.py` generates a manual `ExportOptions.plist` with
`method=app-store-connect`, `destination=export`, team **49PJNAT2WC**, exact
bundle-to-profile UUID mapping, and the certificate SHA-1 fingerprint.
The fingerprint identifies a certificate; it is not a secret or cryptographic
security checksum. `manageAppVersionAndBuildNumber=false` preserves our number.
The archive overrides manual signing on the command line; `project.yml` keeps
**Automatic** signing and the existing team for local development. There are
no `-allowProvisioningUpdates` calls.

`MARKETING_VERSION` in `native/project.yml` is the release version (currently
`1.0`). Both Info plists use `$(MARKETING_VERSION)` and
`$(CURRENT_PROJECT_VERSION)`, not hardcoded values. CI sets a fresh numeric
UTC timestamp `YYYYMMDDHHMMSS` immediately before archiving; serialization
and normal run duration make subsequent runs/reruns distinct and increasing.
Do not upload a manually assigned larger build number in parallel. Change the
marketing version intentionally in `project.yml`; it is not inferred from tags.
The configured AppIcon is supplied by `native/App/Assets.xcassets`.

After export, `xcrun altool` validates then uploads the single IPA using
`API_PRIVATE_KEYS_DIR` and the ASC key/issuer. The script detects supported
flags from the selected tool's `--help`: newer altool uses `--upload-package`
and kebab-case flags; Xcode 26's legacy CLI uses `--upload-app` with
`--apiKey`/`--apiIssuer` because its `--upload-package` also requests numeric
App Store/provider identifiers. Apple's upload documentation still lists
altool. A nonzero validation or upload exits the job; there is no fake success
or fallback that ignores errors. Processing/rejection, export compliance,
tester assignment, and beta review remain in App Store Connect.

### Cleanup/security

A shell EXIT/INT/TERM trap and a separate Actions `if: always()` step call
`native/ci/cleanup.sh`. It restores the exact prior user keychain search list,
deletes only the unique keychain and installed unique profile, and removes the
run's temporary directory (including `.p12`, `.p8`, decoded profile, certificate,
archive, IPA, and local helper files). If restoration fails, cleanup removes
sensitive standalone files but retains the restoration journal and any
undeletable keychain for the `always()` retry, and reports failure. Profiles go in Xcode 16+'s
`~/Library/Developer/Xcode/UserData/Provisioning Profiles`. Existing profiles
and keychains are not replaced/deleted. The default keychain is never changed.
No artifact upload action runs, and no signing material is cached. Shell
tracing is disabled. A hard runner kill can prevent all cleanup; this workflow
uses disposable GitHub-hosted runners, not self-hosted machines.

No `ITSAppUsesNonExemptEncryption` declaration is set automatically. The app
currently uses system HTTPS/authentication APIs, usually eligible for the
standard encryption exemption, but the owner must answer Apple's export
compliance questions accurately for the app and its distribution territories.
If confirmed exempt, explicitly add `ITSAppUsesNonExemptEncryption=false` to
release Info.plist in a reviewed change; otherwise supply Apple's required
compliance information. Do not claim exemption just to bypass processing.

## Local checks (no credentials or upload)

From the repository root:

```sh
python3 -m unittest discover -s native/ci -v
bash -n native/ci/testflight.sh native/ci/cleanup.sh
shellcheck native/ci/*.sh                  # brew install shellcheck
actionlint .github/workflows/ios-testflight.yml # brew install actionlint
plutil -lint native/Config/Info.plist native/Config/Info-Debug.plist
bash native/test-core.sh
xcodegen generate --spec native/project.yml
xcodebuild -project native/KeineMagie.xcodeproj -scheme KeineMagie \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$TMPDIR/KeineMagie-simulator" CODE_SIGNING_ALLOWED=NO build
```

The generated `.xcodeproj` is intentionally ignored; `native/project.yml` is
its source of truth. The Python tests use synthetic metadata, never real Apple
credentials. GitHub uses the selected full Xcode toolchain for `swift test`;
the local wrapper supports this machine's standalone CLT workaround.

Locally verified: Python tests, ShellCheck, actionlint, bash/plist syntax,
XcodeGen 2.46.0 generation, 23 Swift core tests, and an unsigned Release
simulator build with Xcode 27.2 (not the cloud-selected 26.6).
The simulator build emitted only the harmless AppIntents metadata warning
because this app has no AppIntents dependency.

**Not verified / blockers:** GitHub authentication is absent locally, the
workflow is not committed/pushed, and environment/signing/ASC credentials have
not been supplied. A real Xcode 26.6 runner execution, signed device archive,
profile/keychain import, Apple API validation/upload, App Store Connect
processing, compliance, and tester access therefore remain unverified.
The app's other uncommitted source files must be deliberately reviewed and
included before the workflow can build the app on GitHub; do not blindly
commit all local changes. Configure production HTTPS backend/Apple audience
and verify real-device Apple sign-in before distributing to testers.

## References

- [GitHub macOS 26 runner Xcode inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [GitHub: installing Apple certificates on runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Apple: upload builds and supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple: App Store Connect API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- Inspect the selected tool's actual `xcrun altool --help` and
  `xcodebuild -help` when updating Xcode; upload flags differ across versions.

The only external action is checkout, pinned to the verified `v4.2.2` commit
`11bd71901bbe5b1630ceea73d27597364c9af683`; builds/uploads use Apple CLI tools.
