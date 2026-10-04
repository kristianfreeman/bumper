#if os(tvOS)
public import AppCore
public import Observation
public import StoreKit
import SwiftUI
import Instrumentation
import os

/// Theme selection + the one thing we sell: the "Themes & Customization"
/// unlock (StoreKit 2, non-consumable, Family Sharing friendly).
@MainActor
@Observable
public final class ThemeStore {
    public static let productID = "\(Brand.bundleIdentifier).themes.pro"

    public private(set) var theme: Theme
    public private(set) var isUnlocked = false
    public private(set) var product: Product?
    public private(set) var purchaseInFlight = false
    public var customAccentIndex: Int? {
        didSet {
            UserDefaults.standard.set(customAccentIndex, forKey: "appearance.accent")
            apply()
        }
    }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var updates: Task<Void, Never>?
    private static let log = Perf.logger("store")

    public init(settings: AppSettings) {
        self.settings = settings
        theme = Theme.named(settings.themeId)
        isUnlocked = Monetization.themesUnlockedForEveryone
        customAccentIndex = UserDefaults.standard.object(forKey: "appearance.accent") as? Int
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update { await tx.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await refreshEntitlements(); await loadProduct() }
    }

    public func select(_ candidate: Theme) {
        guard !candidate.isPremium || isUnlocked else { return }
        settings.themeId = candidate.id
        apply()
    }

    private func apply() {
        var base = Theme.named(settings.themeId)
        if base.isPremium && !isUnlocked { base = .bumper }
        if isUnlocked, let idx = customAccentIndex, Theme.accentPalette.indices.contains(idx) {
            base = base.withAccent(Theme.accentPalette[idx])
        }
        theme = base
    }

    public func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            Self.log.error("Product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func refreshEntitlements() async {
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let tx) = entitlement, tx.productID == Self.productID, tx.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked || Monetization.themesUnlockedForEveryone
        apply()
    }

    public func purchase() async {
        guard let product, !purchaseInFlight else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            if case .success(.verified(let tx)) = try await product.purchase() {
                await tx.finish()
                await refreshEntitlements()
            }
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
#endif
