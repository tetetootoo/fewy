import StoreKit
import SwiftUI

@MainActor final class Studio: ObservableObject {
    static let productID = "com.bramlen.pocketpress.studio"
    @Published private(set) var unlocked = false
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    @Published var message: String?
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                guard case .verified(let transaction) = result, transaction.productID == Self.productID else { continue }
                await self.refresh()
                await transaction.finish()
            }
        }
    }

    deinit { updates?.cancel() }

    func refresh() async {
        var ownsStudio = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID, transaction.revocationDate == nil {
                ownsStudio = true
            }
        }
        unlocked = ownsStudio
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil { message = "Studio is currently unavailable." }
        } catch { message = "Couldn’t load Studio. Try again shortly." }
    }

    func buy() async {
        guard let product, !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refresh()
                await transaction.finish()
            case .success(.unverified(_, _)): message = "The purchase couldn’t be verified."
            case .pending: message = "Your purchase is awaiting approval."
            case .userCancelled: break
            @unknown default: message = "The purchase status is unavailable."
            }
        } catch { message = "The purchase couldn’t be completed." }
    }

    func restore() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            if !unlocked { message = "No Studio purchase was found." }
        } catch { message = "Couldn’t restore purchases." }
    }
}

struct StudioPaywall: View {
    @ObservedObject var studio: Studio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("FEWY / STUDIO").font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("More room to play.").font(.largeTitle.bold())
            Label("Extra colors for your editions", systemImage: "swatchpalette")
            Label("The Studio sticker collection", systemImage: "sparkles")
            Label("Optional export credit", systemImage: "text.badge.minus")
            if let product = studio.product {
                Button("Unlock Studio · \(product.displayPrice)") {
                    Task { await studio.buy() }
                }.buttonStyle(.borderedProminent)
                Text("One-time purchase").font(.footnote)
            } else {
                Button("Check availability") { Task { await studio.loadProduct() } }
            }
            Button("Restore purchase") { Task { await studio.restore() } }
            if let message = studio.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Spacer()
            Button("Done") { dismiss() }
        }
        .padding(28)
        .disabled(studio.busy)
        .task { await studio.loadProduct() }
        .onChange(of: studio.unlocked) { _, unlocked in if unlocked { dismiss() } }
    }
}
