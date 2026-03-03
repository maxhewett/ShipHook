import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater: ObservableObject {
    private static let fallbackFeedURL = "https://maxhewett.github.io/ShipHook/appcast.xml"
    private static let fallbackPublicKey = "rxaJsfCpTKtpqRubSfkJwKnztT5S8RHsdAueuT+jKck="

    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var feedURLString = ""
    @Published private(set) var hasPublicKey = false

#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
#endif

    init(bundle: Bundle = .main) {
        let bundleFeedURL = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundlePublicKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURL = bundleFeedURL.isEmpty ? Self.fallbackFeedURL : bundleFeedURL
        let publicKey = bundlePublicKey.isEmpty ? Self.fallbackPublicKey : bundlePublicKey
        let configured = !feedURL.isEmpty && !publicKey.isEmpty

        feedURLString = feedURL
        hasPublicKey = !publicKey.isEmpty
        isConfigured = configured

#if canImport(Sparkle)
        if configured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            canCheckForUpdates = true
        } else {
            updaterController = nil
            canCheckForUpdates = false
        }
#else
        canCheckForUpdates = false
#endif
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
#endif
    }
}
