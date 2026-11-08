# TestFlight delivery

## Status and scope

The pipeline is implemented in `.github/workflows/ios-testflight.yml`.
Cloud run **42521748687** reached archive but failed to discover profile
`D78E856B-FB81-4D46-BB18-7DEAB629BCE7` for team `49PJNAT2WC`.
The local fix installs the validated profile at both UUID discovery paths;
a successful signed archive or Apple upload after this fix remains unverified.
No credentials are included. The existing server workflow is independent.

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
`$(CURRENT_PROJECT_VERSION)`, not hardcoded values. CI generates a validated
three-component Apple build number (at most **4/2/2 digits**, first positive)
immediately before archiving. For elapsed UTC seconds `s` since
**2026-01-01 00:00:00Z**, the components are
`1 + s // 10000`, `(s % 10000) // 100`, and `s % 100`.
The supported interval ends exclusively at **2029-03-03 07:00:00Z**;
out-of-range times fail closed, never wrap. Numeric component ordering increases
every second, including day boundaries and serialized reruns; runs started
within the same second share a number (the serialized archive/upload path takes
longer than one second). Timezone offsets do not change the result. This replaces
the invalid 14-digit timestamp; plan a new numbering scheme before the horizon,
without lowering previously uploaded numbers. Do not upload a manually assigned
larger build number in parallel. Change the
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
deletes only the unique keychain and owned installed profiles, and removes the
run's temporary directory (including `.p12`, `.p8`, decoded profile, certificate,
archive, IPA, and local helper files). The profile is installed as
`<validated-UUID>.mobileprovision` in **both** discovery locations:

- `~/Library/MobileDevice/Provisioning Profiles/`
- `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`

Installation checks both destinations first and fails rather than replacing any
existing file or symlink. Atomic, non-overwriting hard links to the decoded
profile identify ownership by device/inode, journaled before installation;
runner temp and HOME must share a filesystem, otherwise installation fails
safely. Cleanup handles a failure after only one destination was installed,
attempts both destinations even if one removal fails, and refuses to delete a
profile replaced by another owner. Unrelated profiles remain untouched.
If cleanup/restoration fails, standalone sensitive files are wiped but the
nonsecret ownership/keychain journal and any undeletable keychain remain for
the `always()` retry; cleanup reports failure. A replaced profile conflict must
be resolved by its owner before retry can complete. The default keychain is
never changed. No artifact upload action runs, and no signing material is
cached. Shell
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

Previously verified before this CI fix: Python tests, ShellCheck, actionlint,
bash/plist syntax,
XcodeGen 2.46.0 generation, 23 Swift core tests, and an unsigned Release
simulator build with Xcode 27.2 (not the cloud-selected 26.6).
The simulator build emitted only the harmless AppIntents metadata warning
because this app has no AppIntents dependency.

**Post-fix local verification:** offline profile/build-number/cleanup tests,
ShellCheck, actionlint, shell syntax, and diff whitespace checks. The tests cover
both UUID discovery paths, preexisting files/symlinks, partial installation,
independent cleanup and recovery retries, and build-number component rollover,
timezone equivalence, format bounds, and horizon rejection.

**Still unverified:** a post-fix Xcode 26.6 cloud archive, Apple validation/upload,
App Store Connect processing, compliance, and tester access. No commit, push,
or cloud rerun was performed as part of this local fix. Configure production
HTTPS backend/Apple audience and verify real-device Apple sign-in before
distributing to testers.

## References

- [GitHub macOS 26 runner Xcode inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [GitHub: installing Apple certificates on runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Apple: upload builds and supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple: App Store Connect API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- Inspect the selected tool's actual `xcrun altool --help` and
  `xcodebuild -help` when updating Xcode; upload flags differ across versions.

The only external action is checkout, pinned to the verified `v4.2.2` commit
`11bd71901bbe5b1630ceea73d27597364c9af683`; builds/uploads use Apple CLI tools.
