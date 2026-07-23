@preconcurrency import SafariServices
import ZoidSafariBridge

public enum SafariWebsiteStateResolver {
  public static func resolve(
    extensionEnabled: Bool?,
    controllerState: SafariWebsiteTrackingState
  ) -> SafariWebsiteTrackingState {
    guard let extensionEnabled else { return .unavailable }
    guard extensionEnabled else { return .extensionDisabled }
    return controllerState
  }
}

public enum SafariExtensionStatusReader {
  public static let extensionIdentifier =
    "com.ziadnasreldin.zoidzero.safari-extension"

  public nonisolated static func isEnabled() async -> Bool? {
    await withCheckedContinuation(isolation: nil) { continuation in
      ZoidGetSafariExtensionState(extensionIdentifier) { enabled, available in
        continuation.resume(returning: available ? enabled : nil)
      }
    }
  }

  public static func openPreferences() {
    SFSafariApplication.showPreferencesForExtension(
      withIdentifier: extensionIdentifier
    ) { _ in }
  }
}
