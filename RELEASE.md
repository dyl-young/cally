# Cally Release Checklist

This checklist is for shipping Cally to other Macs, not just running it locally from Xcode.

## Choose a distribution path

- [ ] **Fastest path:** direct download outside the Mac App Store using Apple Developer ID + notarization.
- [ ] **App Store path:** App Sandbox + App Store Connect submission.

For this repo, direct distribution is the simplest first release.

## Before release

- [ ] Join the Apple Developer Program.
- [ ] Create or confirm a **Developer ID Application** certificate.
- [ ] Set a real signing team in `project.yml`.
- [ ] Keep hardened runtime enabled.
- [ ] Decide whether App Sandbox is needed.
  - [ ] Not required for direct distribution.
  - [ ] Required for Mac App Store distribution.
- [ ] Bump version numbers in `Resources/Info.plist`.
  - [ ] Update `CFBundleShortVersionString`.
  - [ ] Update `CFBundleVersion`.
- [ ] Confirm the app still launches cleanly on a fresh Mac user account.
- [ ] Confirm Google sign-in, token refresh, notifications, login item registration, and hotkey registration still work after signing changes.

## Google OAuth

- [ ] Use a production Google Cloud project, not a personal test-only setup.
- [ ] Configure the OAuth consent screen for external users.
- [ ] Add app name, support email, and privacy policy URL.
- [ ] Add yourself as a test user during verification.
- [ ] Expect Google verification if the app requests sensitive Calendar scopes.
- [ ] Confirm the OAuth redirect flow still works after release signing.

## Build and sign

- [ ] Build a Release archive from Xcode or `xcodebuild`.
- [ ] Confirm the archive is signed with the correct Developer ID identity.
- [ ] Confirm the hardened runtime is present in the final build.
- [ ] Export a distributable artifact.
  - [ ] `.zip` for simple direct downloads.
  - [ ] `.dmg` if you want a more polished install experience.
  - [ ] `.pkg` only if you specifically want an installer package.

## Notarize

- [ ] Upload the exported app, zip, dmg, or pkg to Apple’s notarization service.
- [ ] Fix any signing or entitlements issues reported by notarization.
- [ ] Staple the notarization ticket to the artifact.
- [ ] Re-run Gatekeeper validation on a clean Mac.

## Package for users

- [ ] Put the final artifact somewhere users can download it.
- [ ] Provide a release notes page or changelog.
- [ ] Provide uninstall instructions.
- [ ] Document first launch and Google sign-in.
- [ ] Document what to do if Gatekeeper shows a warning.

## Test the shipped build

- [ ] Test on the minimum supported macOS version.
- [ ] Test on Apple Silicon.
- [ ] Test launch after reboot.
- [ ] Test opening Google Calendar links.
- [ ] Test Meet join actions.
- [ ] Test notifications.
- [ ] Test a clean install with no prior app data.

## Optional later upgrades

- [ ] Add Sparkle if you want self-updating releases.
- [ ] Add a CI workflow to produce signed archives.
- [ ] Add a release script so signing, notarization, stapling, and packaging happen in one command.

## Final pre-publish check

- [ ] Release artifact installs on a clean machine.
- [ ] Gatekeeper accepts it without a manual override.
- [ ] Google sign-in works for a non-test account if the app is public.
- [ ] Version number and release notes match the published artifact.
