import AppKit
import UserNotifications
import ZoidZeroCore

public final class DesktopMeetingNotifier: NSObject, MeetingNotifying,
  UNUserNotificationCenterDelegate, @unchecked Sendable
{
  public override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }

  public func requestAuthorizationIfNeeded() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  public func notify(candidates: [MeetingCandidate]) async {
    guard let first = candidates.first else { return }
    let content = UNMutableNotificationContent()
    content.title =
      candidates.count == 1
      ? "Possible meeting detected"
      : "Possible meetings detected"
    content.body =
      candidates.count == 1
      ? "Review the details before anything is added."
      : "\(candidates.count) meetings are ready for review."
    content.sound = .default
    content.userInfo = ["candidateID": first.id]
    let request = UNNotificationRequest(
      identifier: first.id,
      content: content,
      trigger: nil
    )
    try? await UNUserNotificationCenter.current().add(request)
  }

  nonisolated public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first?.makeKeyAndOrderFront(nil)
      NotificationCenter.default.post(name: .zoidZeroOpenConfirmation, object: nil)
    }
  }
}

extension Notification.Name {
  public static let zoidZeroOpenConfirmation = Notification.Name("zoidZeroOpenConfirmation")
}
