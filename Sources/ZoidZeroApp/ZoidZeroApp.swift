import AppKit
import SwiftUI

@main
struct ZoidZeroApp: App {
  @NSApplicationDelegateAdaptor(ZoidZeroAppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      MeetingCaptureView(model: model)
        .frame(minWidth: 760, minHeight: 620)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 820, height: 680)
  }
}

@MainActor
final class AppTerminationCoordinator {
  static let shared = AppTerminationCoordinator()
  weak var model: AppModel?

  private init() {}
}

@MainActor
final class ZoidZeroAppDelegate: NSObject, NSApplicationDelegate {
  private var isTerminating = false

  func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      sender.windows.first?.makeKeyAndOrderFront(nil)
    }
    return true
  }

  func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    guard let model = AppTerminationCoordinator.shared.model else {
      return .terminateNow
    }
    guard !isTerminating else { return .terminateLater }
    isTerminating = true
    Task {
      await model.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
