import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

@MainActor
final class FewyAds: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published private(set) var ad: NativeAd?
    @Published private(set) var showPrivacyOptions = false
    @Published var privacyError = false
    private var loader: AdLoader?
    private var loadedOnce = false
    @Published private(set) var diagnostic = "Waiting to check consent"

    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var consentTestBusy = false

    func resetConsentTest() async {
        guard !consentTestBusy else { return }
        ad = nil
        loader?.delegate = nil
        loader = nil
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
        // TCF purpose/vendor IDs use one-based positions. Never log the full TC string.
        print("[Fewy Consent Test] GDPR applies=\(gdpr), TCF string present=\(hasTCF), Purpose 1 consent=\(bit("IABTCF_PurposeConsents", at: 1)), Google vendor 755 consent=\(bit("IABTCF_VendorConsents", at: 755)), canRequestAds=\(ConsentInformation.shared.canRequestAds)")
    }
    #endif

    #if DEBUG
    @Published var inspectorError = false
    @Published private(set) var inspectorErrorMessage = ""

    func openAdInspector() {
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
        guard !loadedOnce else { return }
        loadedOnce = true
        #if DEBUG && targetEnvironment(simulator)
        consentTestBusy = true
        defer { consentTestBusy = false }
        #endif
        status("Checking UMP consent")
        do {
            let parameters = RequestParameters()
            #if DEBUG && targetEnvironment(simulator)
            let debugSettings = DebugSettings()
            debugSettings.geography = .EEA
            parameters.debugSettings = debugSettings
            #endif
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
            #if DEBUG && targetEnvironment(simulator)
            logConsentTest()
            #endif
        } catch {
            status("UMP error: \(error.localizedDescription)")
        }
        updatePrivacyState()
        await requestAd()
    }

    func privacyOptions() async {
        #if DEBUG && targetEnvironment(simulator)
        guard !consentTestBusy else { return }
        consentTestBusy = true
        defer { consentTestBusy = false }
        #endif
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            #if DEBUG && targetEnvironment(simulator)
            logConsentTest()
            #endif
            ad = nil
            loader = nil
            updatePrivacyState()
            await requestAd()
        } catch {
            privacyError = true
        }
    }

    private func updatePrivacyState() {
        showPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func requestAd() async {
        #if DEBUG && targetEnvironment(simulator)
        print("[Fewy Consent Test] Request gate: canRequestAds=\(ConsentInformation.shared.canRequestAds)")
        #endif
        guard ConsentInformation.shared.canRequestAds else {
            if !diagnostic.hasPrefix("UMP error:") { status("UMP does not allow an ad request yet") }
            return
        }
        #if DEBUG
        let unit = "ca-app-pub-3940256099942544/3986624511"
        #else
        guard let unit = Bundle.main.object(forInfoDictionaryKey: "GADNativeAdUnitIdentifier") as? String,
              !unit.isEmpty else { return }
        #endif
        await MobileAds.shared.start()
        guard ConsentInformation.shared.canRequestAds, !Task.isCancelled else {
            #if DEBUG && targetEnvironment(simulator)
            print("[Fewy Consent Test] Native request skipped after SDK start: canRequestAds=\(ConsentInformation.shared.canRequestAds), cancelled=\(Task.isCancelled)")
            #endif
            return
        }
        let loader = AdLoader(adUnitID: unit, rootViewController: nil, adTypes: [.native], options: nil)
        self.loader = loader
        loader.delegate = self
        status("Requesting native ad")
        loader.load(Request())
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        guard adLoader === loader, ConsentInformation.shared.canRequestAds else { return }
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
    @StateObject private var ads = FewyAds()

    var body: some View {
        Group {
            if let ad = ads.ad {
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
            Color.clear.frame(height: 0).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                .accessibilityHidden(true)
                .task { await ads.prepare() }
            if ads.showPrivacyOptions {
                Button("Ad privacy options") { Task { await ads.privacyOptions() } }
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
