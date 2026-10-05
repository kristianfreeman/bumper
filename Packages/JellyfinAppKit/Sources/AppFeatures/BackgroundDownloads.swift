import AppCore
import Foundation

/// For the iPhone/iPad app delegate: the system relaunched the app to
/// deliver finished downloads, and waits to be told they're handled.
public enum BackgroundDownloads {
    public static var identifier: String { DownloadStore.backgroundIdentifier }

    public static func handleEvents(_ completion: @escaping () -> Void) {
        nonisolated(unsafe) let done = completion
        SegmentedDownloader.handleSystemEvents { done() }
    }
}
