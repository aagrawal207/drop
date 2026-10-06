import SwiftUI
import StoreKit

/// Optional one-time tips through the App Store. Nothing in the game is unlocked or
/// changed by tipping; the sheet only reports what StoreKit returns.
struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let tips: TipJarService

    // A default argument is evaluated outside the main actor; resolve the singleton in the body.
    init(tips: TipJarService? = nil) {
        self.tips = tips ?? .shared
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.pink)
                        Text("Drop is free, with no ads or tracking. If it has brightened a few minutes of your day, an optional tip helps me keep improving it.")
                        Text("Tips are one-time purchases through Apple. They unlock no features or content. Every part of the game stays free for everyone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if tips.isLoading {
                        HStack { ProgressView(); Text("Loading tips…").foregroundStyle(.secondary) }
                    }
                    ForEach(tips.products, id: \.id) { product in
                        tipRow(product)
                    }
                    if let error = tips.loadError {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await tips.loadProducts() }
                        }
                        .disabled(tips.isLoading || tips.isPurchasing)
                        .accessibilityIdentifier("tipJar.retry")
                    }
                } footer: {
                    if tips.tipCount > 0 {
                        Text(tips.tipCount == 1 ? "One tip recorded on this device. Thank you." : "\(tips.tipCount) tips recorded on this device. Thank you.")
                    }
                }
            }
            .accessibilityIdentifier("tipJar.content")
            .navigationTitle("Support Development")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tipJar.done")
                }
            }
            .task { await tips.loadProducts() }
            // Pending stays inline so a later approval can present its own confirmation.
            .safeAreaInset(edge: .bottom) {
                if tips.state == .pending {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tip pending", systemImage: "clock")
                            .font(.headline)
                        Text("Your purchase is pending with the App Store. It may need approval, such as Ask to Buy. You don't need to try again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Got It") { tips.dismissMessage() }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                }
            }
            .alert(purchaseMessage?.title ?? "", isPresented: Binding(
                get: { purchaseMessage != nil },
                set: { if !$0 { tips.dismissMessage() } }
            ), presenting: purchaseMessage) { _ in
                Button("OK") { tips.dismissMessage() }
            } message: { message in
                Text(message.body)
            }
        }
        .accessibilityIdentifier("tipJar.sheet")
    }

    private var purchaseMessage: (title: String, body: String)? {
        switch tips.state {
        case .thanked:
            return ("Thank you", "Your tip keeps Drop going. Enjoy the next run.")
        case .failed(let message):
            return ("Couldn't confirm tip", message)
        case .idle, .purchasing, .pending:
            return nil
        }
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await tips.purchase(product) }
        } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if tips.state == .purchasing(product.id) {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.pink.opacity(0.14), in: Capsule())
                        .foregroundStyle(.pink)
                }
            }
            .frame(minHeight: 44)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tips.canPurchase)
        .accessibilityIdentifier(product.id)
    }
}
