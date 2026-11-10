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

    private func status(_ message: String) {
        #if DEBUG
        diagnostic = message
        print("[Fewy Ads] " + message)
        #endif
    }

    func prepare() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        status("Checking UMP consent")
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            status("UMP error: \(error.localizedDescription)")
        }
        updatePrivacyState()
        await requestAd()
    }

    func privacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
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
        guard ConsentInformation.shared.canRequestAds, !Task.isCancelled else { return }
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
            #if DEBUG
            Text("Ad test: " + ads.diagnostic).font(.footnote).foregroundStyle(.secondary)
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
