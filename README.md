# Fewy

Native iPhone MVP for iOS 17 and later. Capture private notes, see recent notes in a WidgetKit widget, and turn up to three notes from one day into a 1080 × 1920 Story PNG. The Story editor offers selectable emoji stickers that can be dragged, resized, rotated, or removed. The free design has a pale lemon canvas and a centered credit below the white card.

## Open on a Mac

1. Install Xcode and XcodeGen (`brew install xcodegen`).
2. In this directory run `xcodegen generate`, then open `Fewy.xcodeproj`.
3. Select the Fewy scheme and an iPhone simulator, then Run.
4. For device testing assign your Apple Developer team to both targets. The proposed identifiers use the Bramlen namespace. Register them or replace the app ID, widget ID and App Group in project.yml, the shared group string in Shared/Notes.swift, and the Studio product ID in App/Studio.swift and App/Studio.storekit together. Regenerate the project. Enable the same App Group for both targets.
5. Add the Fewy Notes widget from the home-screen widget gallery. Check that its + button opens the capture field with the keyboard focused.

## Monetization

- **Studio** backgrounds, stickers, and the optional Story credit are included for everyone. There is no purchase or restore flow. Advertising monetization uses consent-gated AdMob.

## Release checks

Build and run both targets in Xcode. On an iPhone, verify capture from a cold widget launch, note edits and deletion, persistence after relaunch, sticker placement in the preview and PNG, image sharing to Photos and messaging, and accessibility with larger text and VoiceOver. Test all Studio features and consent-gated AdMob. Confirm privacy disclosures against the final app, replace launch-site placeholders, publish the privacy/support URLs, and capture actual App Store screenshots before submission.

Simulator validation and remaining production checks are recorded in [the AdMob/UMP review](Launch/AdMob-UMP-Pruefung.md). Device and distribution-signing checks remain necessary. This version stores notes locally and edition edits are session-only. Exports are written to the app's temporary directory for sharing.

### AdMob

The iOS Styles screen includes one consent-gated native ad slot. Debug builds use Google's demo ad unit. Release builds use the configured Fewy unit. Confirm in AdMob that the unit is **Native**. Configure the UMP privacy message in AdMob and verify consent, privacy options, ad attribution, and reporting on a physical device. Before release, complete AdMob app readiness and app-ads.txt verification, review the SDK's current SKAdNetwork list and app privacy disclosures, and confirm the AdChoices reporting flow meets App Review requirements. The web preview does not load the iOS SDK.

Fewy additionally gates GDPR ad requests on Google's Purpose 1 consent and the required purpose/vendor legal bases for Purposes 2, 7, 9 and 10, including publisher restrictions. Personalization consent is not required for an eligible non-personalized request. Rejection blocks SDK initialization from this path and all native requests. Debug simulator consent diagnostics remain local. Run `python3 Tests/test_consent_gate.py` for the isolated TCF regression fixtures.
