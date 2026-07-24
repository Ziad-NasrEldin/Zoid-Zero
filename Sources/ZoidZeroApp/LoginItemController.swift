import AppKit
import OSLog
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
  private let logger = Logger(
    subsystem: "com.ziadnasreldin.zoidzero",
    category: "LoginItem"
  )

  enum State: Equatable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable
    case error(String)

    var title: String {
      switch self {
      case .enabled:
        "Launch at Login: On"
      case .requiresApproval:
        "Launch at Login: Approval Needed"
      case .disabled:
        "Launch at Login: Off"
      case .unavailable:
        "Launch at Login: Unavailable"
      case .error:
        "Launch at Login: Error"
      }
    }
  }

  @Published private(set) var state: State = .disabled

  init(registerIfNeeded: Bool = true) {
    refresh()
    if registerIfNeeded, state == .disabled || state == .unavailable {
      enable()
    }
  }

  func enable() {
    do {
      try SMAppService.mainApp.register()
      refresh()
    } catch {
      state = .error(error.localizedDescription)
      logger.error("Registration failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func disable() {
    do {
      try SMAppService.mainApp.unregister()
      refresh()
    } catch {
      state = .error(error.localizedDescription)
      logger.error("Unregistration failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refresh() {
    switch SMAppService.mainApp.status {
    case .enabled:
      state = .enabled
    case .requiresApproval:
      state = .requiresApproval
    case .notRegistered:
      state = .disabled
    case .notFound:
      state = .unavailable
    @unknown default:
      state = .unavailable
    }
    logger.notice("Status: \(self.state.title, privacy: .public)")
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
