import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

@MainActor
final class FewyAds: NSObject, ObservableObject, NativeAdLoaderDelegate {
    static let shared = FewyAds()

    @Published private(set) var ad: NativeAd?
    @Published private(set) var showPrivacyOptions = false
    @Published var privacyError = false
    private var loader: AdLoader?
    private var loadedOnce = false
    private var adsEnabled = true
    private var consentReady = false
    private var sdkStarted = false
    private var generation = 0
    @Published private(set) var consentTestBusy = false

    func setAdsEnabled(_ enabled: Bool) {
        adsEnabled = enabled
        if !enabled { removeAd() }
    }

    private func removeAd() {
        generation += 1
        ad = nil
        loader?.delegate = nil
        loader = nil
    }

    private var adPermission: String? {
        guard adsEnabled, consentReady, ConsentInformation.shared.canRequestAds else { return nil }
        let information = ConsentInformation.shared
        // UMP remains authoritative outside GDPR; never infer geography from missing TCF bits.
        if information.consentStatus == .notRequired { return "UMP not required" }
        let defaults = UserDefaults.standard
        if (defaults.object(forKey: "IABTCF_gdprApplies") as? NSNumber)?.intValue == 0 {
            return "GDPR not applicable"
        }
        guard (defaults.object(forKey: "IABTCF_gdprApplies") as? NSNumber)?.intValue == 1,
              let tcf = GoogleTCFConsent(defaults: defaults), tcf.allowsNonPersonalized else { return nil }
        return tcf.allowsPersonalized ? "TCF personalized eligible" : "TCF non-personalized eligible"
    }
    @Published private(set) var diagnostic = "Waiting to check consent"

    #if DEBUG && targetEnvironment(simulator)
    func resetConsentTest() async {
        guard !consentTestBusy else { return }
        consentReady = false
        removeAd()
        ConsentInformation.shared.reset()
        showPrivacyOptions = false
        loadedOnce = false
        print("[Fewy Consent Test] Reset UMP consent state")
        await prepare()
    }

    private func logConsentTest() {
        let defaults = UserDefaults.standard
        func bit(_ key: String, at position: Int) -> String {
            guard let value = defaults.string(forKey: key), value.count >= position else {
                return "unavailable"
            }
            let flag = value[value.index(value.startIndex, offsetBy: position - 1)]
            return flag == "0" || flag == "1" ? String(flag) : "unavailable"
        }
        let gdpr = (defaults.object(forKey: "IABTCF_gdprApplies") as? NSNumber)?.stringValue ?? "unavailable"
        let hasTCF = !(defaults.string(forKey: "IABTCF_TCString") ?? "").isEmpty
        let purposes = [1, 2, 3, 4, 7, 9, 10].map {
            "P\($0)=C\(bit("IABTCF_PurposeConsents", at: $0))/LI\(bit("IABTCF_PurposeLegitimateInterests", at: $0))"
        }.joined(separator: " ")
        let tcf = GoogleTCFConsent(defaults: defaults)
        print("[Fewy Consent Test] \(purposes), Google LI=\(bit("IABTCF_VendorLegitimateInterests", at: 755)), restrictions=\(tcf?.restrictions.description ?? "unavailable"), gate=\(adPermission ?? "blocked"), SDK started in process=\(sdkStarted)")
        // TCF purpose/vendor IDs use one-based positions. Never log the full TC string.
        print("[Fewy Consent Test] GDPR applies=\(gdpr), TCF string present=\(hasTCF), Purpose 1 consent=\(bit("IABTCF_PurposeConsents", at: 1)), Google vendor 755 consent=\(bit("IABTCF_VendorConsents", at: 755)), canRequestAds=\(ConsentInformation.shared.canRequestAds)")
    }
    #endif

    #if DEBUG
    @Published var inspectorError = false
    @Published private(set) var inspectorErrorMessage = ""

    func openAdInspector() {
        guard sdkStarted, !consentTestBusy, adPermission != nil else {
            status("Ad Inspector unavailable before an allowed SDK start")
            return
        }
        // The SDK automatically treats iOS simulators as test devices.
        // Present only: preserve UMP consent and the existing ad request history.
        MobileAds.shared.presentAdInspector(from: nil) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                let failure = error as NSError
                self?.inspectorErrorMessage = "\(failure.domain) (\(failure.code)): \(failure.localizedDescription)\n\(failure.userInfo)"
                self?.inspectorError = true
            }
        }
    }
    #endif

    private func status(_ message: String) {
        #if DEBUG
        diagnostic = message
        print("[Fewy Ads] " + message)
        #endif
    }

    func prepare() async {
        guard !loadedOnce, !consentTestBusy else { return }
        loadedOnce = true
        consentTestBusy = true
        defer { consentTestBusy = false }
        status("Checking UMP consent")
        do {
            let parameters = RequestParameters()
            #if DEBUG && targetEnvironment(simulator)
            let debugSettings = DebugSettings()
            debugSettings.geography = .EEA
            parameters.debugSettings = debugSettings
            #endif
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if adsEnabled { try await ConsentForm.loadAndPresentIfRequired(from: nil) }
            consentReady = true
            #if DEBUG && targetEnvironment(simulator)
            logConsentTest()
            #endif
        } catch {
            consentReady = false
            removeAd()
            status("UMP error: \(error.localizedDescription)")
        }
        updatePrivacyState()
        await requestAd()
    }

    func privacyOptions() async {
        guard !consentTestBusy else { return }
        consentTestBusy = true
        defer { consentTestBusy = false }
        consentReady = false
        removeAd() // Invalidate in-flight callbacks before presenting a potentially changed choice.
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            consentReady = true
            #if DEBUG && targetEnvironment(simulator)
            logConsentTest()
            #endif
        } catch {
            privacyError = true
            status("UMP privacy options error: \(error.localizedDescription)")
        }
        updatePrivacyState()
        await requestAd()
    }

    private func updatePrivacyState() {
        showPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func requestAd() async {
        #if DEBUG && targetEnvironment(simulator)
        print("[Fewy Consent Test] Request gate: canRequestAds=\(ConsentInformation.shared.canRequestAds)")
        #endif
        guard let permission = adPermission else {
            removeAd()
            status("Native request blocked by consent; Ads SDK not started from this path")
            return
        }
        let requestGeneration = generation
        #if DEBUG
        let unit = "ca-app-pub-3940256099942544/3986624511"
        #else
        guard let unit = Bundle.main.object(forInfoDictionaryKey: "GADNativeAdUnitIdentifier") as? String,
              !unit.isEmpty else { return }
        #endif
        if !sdkStarted {
            status("Starting Ads SDK: \(permission)")
            await MobileAds.shared.start()
            sdkStarted = true
        }
        guard generation == requestGeneration, adPermission != nil, !Task.isCancelled else {
            status("Native request skipped after SDK start: consent changed or task cancelled")
            return
        }
        let loader = AdLoader(adUnitID: unit, rootViewController: nil, adTypes: [.native], options: nil)
        self.loader = loader
        loader.delegate = self
        status("Requesting native ad")
        loader.load(Request())
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        guard adLoader === loader, adPermission != nil else { return }
        status("Native ad loaded")
        ad = nativeAd
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        guard adLoader === loader else { return }
        let failure = error as NSError
        status("Load failed [\(failure.domain) \(failure.code)]: \(failure.localizedDescription)")
        ad = nil
    }
}

struct FewyAdSection: View {
    let adsEnabled: Bool
    @StateObject private var ads = FewyAds.shared

    var body: some View {
        Group {
            if adsEnabled, let ad = ads.ad {
                Section {
                    FewyNativeAdCard(ad: ad)
                        .frame(height: 250)
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            Button("Reset consent test") { Task { await ads.resetConsentTest() } }
                .disabled(ads.consentTestBusy)
            #endif
            #if DEBUG
            Text("Ad test: " + ads.diagnostic).font(.footnote).foregroundStyle(.secondary)
            Button("Open Ad Inspector") { ads.openAdInspector() }
                .alert("Couldn’t open Ad Inspector", isPresented: $ads.inspectorError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(ads.inspectorErrorMessage)
                }
            #endif
            if ads.showPrivacyOptions {
                Button("Ad privacy options") { Task { await ads.privacyOptions() } }
                    .disabled(ads.consentTestBusy)
            }
        }
        .alert("Couldn’t open ad privacy options", isPresented: $ads.privacyError) {
            Button("OK", role: .cancel) {}
        }
    }
}

private struct FewyNativeAdCard: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let view = NativeAdView()
        let badge = UILabel()
        badge.text = "Ad"
        badge.font = .preferredFont(forTextStyle: .caption2)
        badge.textColor = .secondaryLabel

        let choices = AdChoicesView()
        let top = UIStackView(arrangedSubviews: [badge, UIView(), choices])
        top.alignment = .center
        choices.widthAnchor.constraint(equalToConstant: 24).isActive = true
        choices.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let headline = UILabel()
        headline.font = .preferredFont(forTextStyle: .headline)
        headline.numberOfLines = 2
        let media = MediaView()
        media.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let button = UIButton(type: .system)
        button.isUserInteractionEnabled = false
        button.contentHorizontalAlignment = .leading

        let stack = UIStackView(arrangedSubviews: [top, headline, media, button])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.adChoicesView = choices
        view.headlineView = headline
        view.mediaView = media
        view.callToActionView = button
        return view
    }

    func updateUIView(_ view: NativeAdView, context: Context) {
        guard view.nativeAd !== ad else { return }
        (view.headlineView as? UILabel)?.text = ad.headline
        view.mediaView?.mediaContent = ad.mediaContent
        (view.callToActionView as? UIButton)?.setTitle(ad.callToAction, for: .normal)
        view.callToActionView?.isHidden = ad.callToAction == nil
        view.nativeAd = ad
    }
}

// Read-only Google (GVL vendor 755) gate. UMP/Google still consume the original TC string.
// Google requirements: https://support.google.com/admob/answer/9760862
// Core encoding: IAB Tech Lab TCF v2 Consent String and Vendor List Formats.
private struct GoogleTCFConsent {
    let purposes: [Bool]
    let interests: [Bool]
    let vendorConsent: Bool
    let vendorInterest: Bool
    let restrictions: [Int: Int]

    init?(defaults: UserDefaults) {
        guard let string = defaults.string(forKey: "IABTCF_TCString") else { return nil }
        do {
            let segments = string.components(separatedBy: ".")
            var core = try TCFBits(segments[0])
            guard try core.read(6) == 2 else { return nil }
            try core.skip(126) // timestamps, CMP, language, GVL version
            let policy = try core.read(6)
            try core.skip(14) // service-specific, non-standard stacks, special features
            purposes = try (0..<24).map { _ in try core.read(1) == 1 }
            interests = try (0..<24).map { _ in try core.read(1) == 1 }
            try core.skip(13) // PurposeOneTreatment never substitutes for explicit Purpose 1 consent.
            vendorConsent = try core.googleVendor()
            vendorInterest = try core.googleVendor()
            var limits: [Int: Int] = [:]
            for _ in 0..<(try core.read(12)) {
                let purpose = try core.read(6)
                let restriction = try core.read(2)
                guard (1...24).contains(purpose), restriction < 3 else { return nil }
                if try core.googleInRanges(maxVendor: 65535) {
                    guard limits[purpose] == nil else { return nil }
                    limits[purpose] = restriction
                }
            }
            restrictions = limits
            // TCF 2.3 requires disclosure, also when legitimate interest is the legal basis.
            if policy >= 5 {
                var disclosed = false
                for segment in segments.dropFirst() {
                    var bits = try TCFBits(segment)
                    if try bits.read(3) == 1 { disclosed = try bits.googleVendor() }
                }
                guard disclosed else { return nil }
            }
            // Missing or inconsistent UMP projections fail closed rather than inventing signals.
            func matches(_ key: String, _ flags: [Bool]) -> Bool {
                guard let value = defaults.string(forKey: key), (10...24).contains(value.count) else { return false }
                return Array(value)[...] == flags.prefix(value.count).map { $0 ? Character("1") : Character("0") }[...]
            }
            func matchesVendor(_ key: String, _ flag: Bool) -> Bool {
                guard let value = defaults.string(forKey: key), value.count >= 755 else { return false }
                return value[value.index(value.startIndex, offsetBy: 754)] == (flag ? "1" : "0")
            }
            guard matches("IABTCF_PurposeConsents", purposes),
                  matches("IABTCF_PurposeLegitimateInterests", interests),
                  matchesVendor("IABTCF_VendorConsents", vendorConsent),
                  matchesVendor("IABTCF_VendorLegitimateInterests", vendorInterest) else { return nil }
        } catch { return nil }
    }

    private func consent(_ purpose: Int) -> Bool {
        restrictions[purpose] != 0 && restrictions[purpose] != 2 && vendorConsent && purposes[purpose - 1]
    }

    private func flexibleBasis(_ purpose: Int) -> Bool {
        switch restrictions[purpose] {
        case 0: return false
        case 1: return vendorConsent && purposes[purpose - 1]
        // Google defaults to LI for these flexible purposes; consent requires a publisher restriction.
        default: return vendorInterest && interests[purpose - 1]
        }
    }

    var allowsNonPersonalized: Bool { consent(1) && [2, 7, 9, 10].allSatisfy(flexibleBasis) }
    var allowsPersonalized: Bool { allowsNonPersonalized && consent(3) && consent(4) }
}

private struct TCFBits {
    private let bits: [UInt8]
    private var offset = 0
    private enum Invalid: Error { case encoding }

    init(_ segment: String) throws {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !segment.isEmpty, segment.count <= 20000 else { throw Invalid.encoding }
        var result: [UInt8] = []
        for character in segment {
            guard let value = alphabet.firstIndex(of: character) else { throw Invalid.encoding }
            result += (0..<6).reversed().map { UInt8((value >> $0) & 1) }
        }
        bits = result
    }

    mutating func read(_ count: Int) throws -> Int {
        guard count >= 0, offset + count <= bits.count else { throw Invalid.encoding }
        defer { offset += count }
        return bits[offset..<(offset + count)].reduce(0) { ($0 << 1) | Int($1) }
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= bits.count else { throw Invalid.encoding }
        offset += count
    }

    mutating func googleVendor() throws -> Bool {
        let maximum = try read(16)
        if try read(1) == 1 { return try googleInRanges(maxVendor: maximum) }
        var allowed = false
        for vendor in 0..<maximum {
            let flag = try read(1)
            if vendor == 754 { allowed = flag == 1 }
        }
        return allowed
    }

    mutating func googleInRanges(maxVendor: Int) throws -> Bool {
        var found = false
        var previous = 0
        for _ in 0..<(try read(12)) {
            let range = try read(1) == 1
            let first = try read(16)
            let last = range ? try read(16) : first
            guard first > previous, last >= first, last <= maxVendor else { throw Invalid.encoding }
            if first <= 755 && last >= 755 { found = true }
            previous = last
        }
        return found
    }
}
