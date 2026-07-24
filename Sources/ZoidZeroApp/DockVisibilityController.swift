import AppKit
import OSLog
import ZoidZeroCore

@MainActor
final class DockVisibilityController: ObservableObject {
  @Published private(set) var showsInDock: Bool
  @Published private(set) var errorMessage: String?

  private let application: NSApplication
  private let preference: DockVisibilityPreference
  private let logger = Logger(
    subsystem: "com.ziadnasreldin.zoidzero",
    category: "dock-visibility"
  )

  init(
    application: NSApplication = .shared,
    preference: DockVisibilityPreference = DockVisibilityPreference()
  ) {
    self.application = application
    self.preference = preference
    showsInDock = preference.showsInDock
    apply(showsInDock: showsInDock, persist: false)
  }

  func setShowsInDock(_ showsInDock: Bool) {
    apply(showsInDock: showsInDock, persist: true)
  }

  private func apply(showsInDock requestedValue: Bool, persist: Bool) {
    let policy: NSApplication.ActivationPolicy = requestedValue ? .regular : .accessory
    guard application.setActivationPolicy(policy) else {
      showsInDock = application.activationPolicy() == .regular
      errorMessage = "Zoid 0 could not update its Dock setting."
      logger.error(
        "Failed to set activation policy to \(String(describing: policy), privacy: .public)"
      )
      return
    }

    showsInDock = requestedValue
    errorMessage = nil
    if persist {
      preference.setShowsInDock(requestedValue)
    }
  }
}
