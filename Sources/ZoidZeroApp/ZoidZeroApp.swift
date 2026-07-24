import AppKit
import SwiftUI
import ZoidZeroCore

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
    .commands {
      CommandGroup(after: .appSettings) {
        Toggle(
          "Show Zoid 0 in Dock",
          isOn: Binding(
            get: { appDelegate.showsInDock },
            set: { appDelegate.setShowsInDock($0) }
          )
        )
      }
    }
  }
}

@MainActor
final class AppTerminationCoordinator {
  static let shared = AppTerminationCoordinator()
  weak var model: AppModel?

  private init() {}
}

@MainActor
final class ZoidZeroAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private static let mainWindowFrameKey = "ZoidZero.MainWindowFrame"

  private var isTerminating = false
  private let launchUptime = ProcessInfo.processInfo.systemUptime
  private var dockVisibility: DockVisibilityController?
  private var loginItem: LoginItemController?
  private weak var observedMainWindow: NSWindow?
  private var statusItem: NSStatusItem?
  private var uptimeTimer: Timer?

  func applicationWillFinishLaunching(_ notification: Notification) {
    dockVisibility = DockVisibilityController()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    loginItem = LoginItemController()
    installStatusItem()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    guard let application = notification.object as? NSApplication else { return }
    Task { @MainActor [weak self, weak application] in
      await Task.yield()
      self?.observeMainWindow(in: application)
    }
  }

  private func observeMainWindow(in application: NSApplication?) {
    guard
      let application,
      let window = application.windows.first(where: \.canBecomeMain),
      observedMainWindow !== window
    else { return }
    if let savedFrame = UserDefaults.standard.string(
      forKey: Self.mainWindowFrameKey
    ) {
      let frame = NSRectFromString(savedFrame)
      let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
        ?? window.screen
        ?? NSScreen.main
      window.setFrame(
        window.constrainFrameRect(frame, to: screen),
        display: true
      )
    }
    observedMainWindow = window
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowFrameDidChange(_:)),
      name: NSWindow.didMoveNotification,
      object: window
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowFrameDidChange(_:)),
      name: NSWindow.didResizeNotification,
      object: window
    )
  }

  @objc private func windowFrameDidChange(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    UserDefaults.standard.set(
      NSStringFromRect(window.frame),
      forKey: Self.mainWindowFrameKey
    )
  }

  static func openApp() {
    let application = NSApplication.shared
    application.activate(ignoringOtherApps: true)
    application.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
  }

  var showsInDock: Bool {
    dockVisibility?.showsInDock ?? true
  }

  func setShowsInDock(_ showsInDock: Bool) {
    dockVisibility?.setShowsInDock(showsInDock)
    if showsInDock {
      Self.openApp()
    }
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.autosaveName = "com.ziadnasreldin.zoidzero.status"
    item.isVisible = true
    guard let button = item.button else { return }

    let icon = NSApplication.shared.applicationIconImage.copy() as? NSImage
    icon?.size = NSSize(width: 18, height: 18)
    icon?.isTemplate = false
    button.image = icon
    button.imagePosition = .imageLeading
    button.toolTip = "Zoid 0 is active"

    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    statusItem = item
    updateUptime()

    let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateUptime()
      }
    }
    timer.tolerance = 5
    RunLoop.main.add(timer, forMode: .common)
    uptimeTimer = timer
  }

  private func updateUptime() {
    let uptime = UptimeFormatter.concise(
      elapsed: ProcessInfo.processInfo.systemUptime - launchUptime
    )
    statusItem?.button?.title = " \(uptime)"
    statusItem?.button?.setAccessibilityLabel("Zoid 0 active for \(uptime)")
  }

  func menuWillOpen(_ menu: NSMenu) {
    loginItem?.refresh()
    rebuildMenu(menu)
  }

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()
    menu.addItem(
      withTitle: "Open Zoid 0",
      action: #selector(openFromMenu),
      keyEquivalent: ""
    )
    menu.addItem(.separator())

    let activeItem = NSMenuItem(title: "Zoid 0 is active", action: nil, keyEquivalent: "")
    activeItem.isEnabled = false
    menu.addItem(activeItem)

    if let loginItem {
      let stateItem = NSMenuItem(
        title: loginItem.state.title,
        action: nil,
        keyEquivalent: ""
      )
      stateItem.isEnabled = false
      menu.addItem(stateItem)

      switch loginItem.state {
      case .enabled:
        menu.addItem(
          withTitle: "Turn Off Launch at Login",
          action: #selector(disableLoginItem),
          keyEquivalent: ""
        )
      case .requiresApproval:
        menu.addItem(
          withTitle: "Open Login Items Settings",
          action: #selector(openLoginItemsSettings),
          keyEquivalent: ""
        )
      case .disabled, .unavailable, .error:
        menu.addItem(
          withTitle: "Enable Launch at Login",
          action: #selector(enableLoginItem),
          keyEquivalent: ""
        )
      }

      if case .error(let message) = loginItem.state {
        let errorItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        menu.addItem(errorItem)
      }
    }

    if let dockVisibility {
      menu.addItem(.separator())
      let dockItem = NSMenuItem(
        title: "Show Zoid 0 in Dock",
        action: #selector(toggleDockVisibility),
        keyEquivalent: ""
      )
      dockItem.state = dockVisibility.showsInDock ? .on : .off
      menu.addItem(dockItem)

      if let message = dockVisibility.errorMessage {
        let errorItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        menu.addItem(errorItem)
      }
    }

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Zoid 0",
      action: #selector(quitFromMenu),
      keyEquivalent: "q"
    )
    for item in menu.items where item.action != nil {
      item.target = self
    }
  }

  @objc private func openFromMenu() {
    Self.openApp()
  }

  @objc private func enableLoginItem() {
    loginItem?.enable()
  }

  @objc private func disableLoginItem() {
    loginItem?.disable()
  }

  @objc private func openLoginItemsSettings() {
    loginItem?.openLoginItemsSettings()
  }

  @objc private func toggleDockVisibility() {
    guard let dockVisibility else { return }
    setShowsInDock(!dockVisibility.showsInDock)
  }

  @objc private func quitFromMenu() {
    NSApplication.shared.terminate(nil)
  }

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
      Self.openApp()
    }
    return true
  }

  func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    if let window = sender.windows.first(where: \.canBecomeMain) {
      UserDefaults.standard.set(
        NSStringFromRect(window.frame),
        forKey: Self.mainWindowFrameKey
      )
    }
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
