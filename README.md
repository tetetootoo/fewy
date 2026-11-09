# Fewy

Native iPhone MVP for iOS 17 and later. Capture private notes, see recent notes in a WidgetKit widget, and turn up to three notes from one day into a 1080 × 1920 Story PNG. The Story editor offers selectable emoji stickers that can be dragged, resized, rotated, or removed. The free design has a pale lemon canvas and a centered credit below the white card.

## Open on a Mac

1. Install Xcode and XcodeGen (`brew install xcodegen`).
2. In this directory run `xcodegen generate`, then open `Fewy.xcodeproj`.
3. Select the Fewy scheme and an iPhone simulator, then Run. Under Edit Scheme → Run → Options, select App/Studio.storekit if it is not already selected. This is local purchase testing only.
4. For device testing assign your Apple Developer team to both targets. The proposed identifiers use the Bramlen namespace. Register them or replace the app ID, widget ID and App Group in project.yml, the shared group string in Shared/Notes.swift, and the Studio product ID in App/Studio.swift and App/Studio.storekit together. Regenerate the project. Enable the same App Group for both targets.
5. Add the Fewy Notes widget from the home-screen widget gallery. Check that its + button opens the capture field with the keyboard focused.

## Monetization

- **Studio** is a non-consumable StoreKit 2 purchase. It unlocks extra stickers, two extra colors, hides the sponsor placement, and lets the user remove the Story credit. The app uses the localized store price. The local test product uses 12.99 as a starting point.
- In App Store Connect create the matching non-consumable, set pricing and localizations, add review details, and submit it with the initial app version. Test purchase, pending, cancellation, restore, refund, and revocation with the Apple testing environment before release.
- **Sponsored placement** appears only in Styles for free users and is labeled Sponsored. Copy Launch/Sponsor.example.json to App/Sponsor.json, substitute a real partner and an HTTPS destination, then regenerate the project. A missing or invalid sponsor hides the placement. The implementation uses a direct sponsor link and bundled configuration, so changing a campaign requires a new app build. Sell the placement as a fixed-fee sponsorship directly. No ad network, impression billing, or tracking SDK is configured.

## Release checks

Build and run both targets in Xcode. On an iPhone, verify capture from a cold widget launch, note edits and deletion, persistence after relaunch, sticker placement in the preview and PNG, image sharing to Photos and messaging, and accessibility with larger text and VoiceOver. Test StoreKit and the sponsor with both free and Studio access. Confirm privacy disclosures against the final app, replace launch-site placeholders, publish the privacy/support URLs, and capture actual App Store screenshots before submission.

Source was prepared in a Linux workspace. Xcode compilation, signing, simulator and device tests remain to be performed on a Mac. This version stores notes locally and edition edits are session-only. Exports are written to the app's temporary directory for sharing.

### AdMob

The iOS Styles screen includes one consent-gated native ad slot. Debug builds use Google's demo ad unit. Release builds use the configured Fewy unit. Confirm in AdMob that the unit is **Native**. Configure the UMP privacy message in AdMob and verify consent, privacy options, ad attribution, and reporting on a physical device. Before release, complete AdMob app readiness and app-ads.txt verification, review the SDK's current SKAdNetwork list and app privacy disclosures, and confirm the AdChoices reporting flow meets App Review requirements. The web preview does not load the iOS SDK.
