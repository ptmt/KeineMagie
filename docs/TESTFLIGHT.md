# TestFlight delivery

## Status and scope

The pipeline is implemented in `.github/workflows/ios-testflight.yml`.
Cloud run **42524035277** at `ac630ae03e8a1951b8cdfe8f6be35b49ba62485c`
failed at profile lookup on Xcode **26.6 (17F113)** even after dual-path
installation. The archive requested UUID `D78E856B-FB81-4D46-BB18-7DEAB629BCE7`.
This revision uses independent regular copies, preserves the profile's exact
UUID spelling, selects its validated **Name** plus explicit UUID, and adds
sanitized installation/resolved-Xcode-setting diagnostics. A successful signed
archive or Apple upload after these changes remains unverified.

### Evidence and limits of the diagnosis

- The failed job passed CMS metadata/certificate validation, private-key identity
  lookup, and both profile install calls; it failed at `GatherProvisioningInputs`
  with “No profile for team … matching … found”, not at codesign or upload.
- Working comparison: `ptmt/weirdstats` run **42523087367**, Xcode **26.3
  (17C529)**, copied regular files to both paths, used the original lowercase
  UUID as specifier, and packaged the modern-directory profile. Its signed
  archive and Apple upload succeeded using the **same certificate fingerprint**
  `FEC48BE6EA231D59959312D382A060EA39FA29A2`. A generic invalid certificate is
  therefore not supported by the evidence; the keychain setup is not identical.
- Our old installer created three links to one inode. The validator also
  uppercased UUIDs before putting them in filenames/specifiers. Both are
  concrete differences, not demonstrated Xcode bugs. Existing logs do **not**
  reveal the raw profile Name/UUID spelling, installed sizes, or scanner contents.
  They cannot establish whether hardlinks, UUID case/specifier matching, or an
  Xcode-version difference caused rejection. We do not claim a proven root cause.
- Keep Xcode 26.6 pinned for the next run; changing it simultaneously would
  confound the comparison. If lookup still fails despite verified regular copies
  and exact Name/UUID, compare 26.3 only if available in the live runner inventory.
- New diagnostics decode **only the two owned profiles**, printing path,
  existence, size, regular-file flag, link count, Name and UUID. The selected
  Xcode's `-showBuildSettings -json` output is privately captured and reduced to
  signing style/team/profile settings. `EXPANDED_PROVISIONING_PROFILE` may be
  absent: these settings are **not** proof of scanner acceptance. The real archive
  remains the discovery test. No full plist, certificate list, API key, private
  key, or unrestricted environment/build-settings dump is printed.
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
existing file or symlink. Each destination is exclusively created using
`O_CREAT|O_EXCL` with mode 0600 and filled by copying bytes (no hardlinks and no
same-filesystem requirement). Its device/inode and birth time when available are
journaled via atomic journal replacement **before** sensitive bytes are copied.
Atomicity here means non-overwriting creation/journal replacement, not an atomic
publication of the completed copy; Xcode starts only after both copies finish.
An ordinary journal-write failure removes the still-empty reserved file if its
identity matches. A hard process kill between creation and journal persistence
can leave an empty file rather than risk deleting an unowned replacement.
Cleanup handles copy/partial-install failures,
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

## Recurring Missing Compliance: native encryption assessment

The user reports builds `2703.29.40`, `2702.55.92`, and `2700.67.79` as
**Missing Compliance**, with the older `2695` build associated with the **ME**
group. These are reported portal observations, not a live portal verification.
Both native source Info plists previously omitted
`ITSAppUsesNonExemptEncryption`; Apple's key documentation says omission causes
the export questionnaire on each upload. Both now explicitly declare the plist
**Boolean false**, meaning **no non-exempt encryption**, not “no encryption.”
This changes future binaries only; it cannot repair already uploaded builds.

### Evidence for the declaration

The reviewed distributed native app uses only Apple's system security APIs:

- `native/project.yml`: app sources are `App`; the only package is local
  `KeineMagieCore` at `Core`. `native/Core/Package.swift` has no external package
  dependencies or binary targets. No embedded third-party crypto implementation
  was found in these app/package sources or dependency declarations.
- `native/Core/Sources/KeineMagieCore/AuthClient.swift`, `network`: ephemeral
  `URLSession` for HTTPS. `ServerEndpoint.swift` requires HTTPS, except Debug
  simulator loopback. No custom TLS implementation is shipped.
- `native/App/AppleLoginCoordinator.swift`: system `AuthenticationServices`
  Sign in with Apple; the challenge nonce is supplied by the server and passed
  unchanged, without local hashing. Identity tokens are forwarded for server
  verification, not signed or decrypted by a custom native implementation.
- `native/App/TokenStore.swift`: system Security/Keychain `SecItem*` storage of
  the bearer credential, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `native/App/ChatGPTSafariView.swift`: system `SFSafariViewController` for
  provider consent. `OAuthLoopback.swift` uses system Network plain TCP bound
  only to `127.0.0.1` for the ephemeral HTTP callback, not a custom encrypted
  protocol. OAuth state comparisons and UUID attempt IDs are not encryption.
- Searches found **no CryptoKit import, SHA256 implementation/call,
  CommonCrypto, bundled OpenSSL, custom cipher, key agreement, signing, or
  encryption/decryption implementation in native App/Core sources**. Do not
  assume native nonce hashing merely because other Apple-login examples use it.
- The separate Go backend **does** use cryptography: e.g. `server/provider.go`
  AES-GCM credential storage and SHA-256 PKCE, `auth_store.go` session hashes,
  and `apple_verify.go` RSA verification. This code runs on the server and is
  not linked, copied, or bundled into the iOS app by the native project. CI
  OpenSSL commands handle signing assets on the runner, not app runtime crypto.

Apple's [encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
explicitly says encryption limited to the Apple operating system requires **no
documentation in App Store Connect**. Its [developer guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
explicitly names HTTPS via `URLSession` as typically exempt and directs a
Boolean `NO` for only exempt encryption, including linked libraries. The
[key reference](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
also defines `NO` for no encryption **or only exempt encryption**. On this
reviewed native code/dependency scope, `false` is supported; it is not a claim
that all code in the repository has no crypto or a blanket legal determination.
Reassess if native dependencies, bundled code, or cryptographic features change.
The account owner remains responsible for classification, distribution-country
answers, and any government reporting requirements; exemption from Apple's
upload-document requirement does not itself settle all export obligations.

### Existing uploaded builds: account-owner action only

No portal changes, tester assignment, signing secrets, or uploads are performed
by this fix. An Account Holder, Admin, or App Manager must follow Apple's
[beta-build compliance instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds):

1. Open **App Store Connect → Apps → Keine Magie → TestFlight → iOS**.
   For the desired already-uploaded build (newest reported: `2703.29.40`), click
   **Manage** beside **Missing Compliance**, or open its build details and
   **Provide Export Compliance Information**. Repeat for older missing builds
   only if they also need to be made available; clearing one does not change
   another build's uploaded plist.
2. Answer the actual question wording truthfully, using the reviewed evidence:
   - If asked whether the app **uses encryption at all**, **Yes**: it uses
     system HTTPS, authentication, and Keychain. Do not answer “No encryption”
     merely because the plist non-exempt flag is false.
   - If asked whether it uses **non-exempt encryption**, the current native
     assessment supports **No**.
   - If asked which algorithms it implements, choose the option meaning
     **none of the listed algorithms / only encryption within Apple's OS**,
     if offered. It does not implement proprietary algorithms or standard
     algorithms **instead of, or in addition to, Apple's OS implementation**.
     Do not select a custom/independently implemented algorithm just because
     system HTTPS internally uses standard algorithms.
   - If asked whether encryption is limited to the Apple operating system,
     the reviewed native implementation supports **Yes**. Answer any exemption
     and territory questions from the actual app/distribution facts; do not
     invent a France/distribution answer or a CCATS/documentation code.
   If the wording/options do not match these facts, stop and review Apple's
   [determination guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)
   rather than guessing. Save the truthful declaration; if Apple instead
   requires documentation, supply it and wait for approval.
3. Read back the exact build's status after saving. Once compliance is resolved
   and it is eligible for internal testing, open **Internal Testing → ME →
   Builds → Add Builds**, select that exact build and save (or its build-detail
   **Groups** equivalent). Verify the build lists **ME** and the ME group's
   builds list contains it. The older `2695` membership does not prove newer
   builds are assigned; upload success alone does not prove tester availability.
4. A future binary containing this metadata should avoid this recurring
   questionnaire for the reviewed exempt usage. Verify processing, compliance
   status, and ME assignment separately after publication; none is claimed
   verified locally.

### Regression verification

`native/ci/test_app_metadata.py` asserts a real Boolean false in both tracked
source plists before XcodeGen. Its effective-plist test checks the actual built
app's bundle ID and encryption value when `KM_BUILT_APP_PLIST` is set; it skips
only that integration check before a build. The validation workflow explicitly
sets this path and runs the test after its Release simulator build, so generated
or processed metadata cannot silently drop the declaration.

RED was observed for both missing source keys and the actual pre-fix Release
built plist (`None is not False`). GREEN was observed after adding the keys:
Release and Debug unsigned simulator builds succeeded under local Xcode 27.2,
and all three metadata tests passed against each effective built app plist.
The full Python CI suite passes all 32 tests when given the built Release plist
(the pre-build run intentionally skips the one effective-plist test). XcodeGen
and source/built-plist `plutil` validation pass. Local unsigned simulator output
is not proof of signed archive/upload, portal compliance, or tester availability.

To rerun the effective check after the build below:

```sh
KM_BUILT_APP_PLIST="$TMPDIR/KeineMagie-simulator/Build/Products/Release-iphonesimulator/KeineMagie.app/Info.plist" \
  python3 -m unittest discover -s native/ci -p test_app_metadata.py -v
```

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

**Post-fix local verification:** **22** offline profile/build-number/cleanup tests,
ShellCheck, actionlint, shell syntax, and diff whitespace checks. Added regressions
cover independent mode-0600 single-link copies, copy/journal failures, a racing
owner, exact UUID case preservation, validated Name/control-character rejection,
and allowlisted diagnostics that never print unrelated plist fields. Existing
tests still cover both UUID discovery paths, preexisting files/symlinks,
independent cleanup/recovery retries, and build-number rollover/bounds.

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
