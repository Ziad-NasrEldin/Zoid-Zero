import EventKit
import Foundation
import ZoidZeroCore

public actor AppleSchedulingService: MeetingScheduling {
  private let store = EKEventStore()

  public init() {}

  public func requestPermissionsIfNeeded() async {
    _ = try? await store.requestWriteOnlyAccessToEvents()
    _ = try? await store.requestFullAccessToReminders()
  }

  public func schedule(_ meeting: ConfirmedMeeting) async throws -> SchedulingReceipt {
    try await requireAccess(to: .event)
    try await requireAccess(to: .reminder)

    let eventRequest = CalendarEventRequest(meeting: meeting)
    let event = EKEvent(eventStore: store)
    event.calendar = store.defaultCalendarForNewEvents
    event.title = eventRequest.title
    event.notes = eventRequest.notes
    event.startDate = eventRequest.start
    event.endDate = eventRequest.end
    let reminderRequest = ReminderRequest(meeting: meeting)
    guard let reminderCalendar = store.defaultCalendarForNewReminders() else {
      throw SchedulingError.noReminderCalendar
    }
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = reminderCalendar
    reminder.title = reminderRequest.title
    reminder.dueDateComponents = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .timeZone],
      from: reminderRequest.due
    )
    do {
      try store.save(event, span: .thisEvent, commit: false)
      try store.save(reminder, commit: false)
      try store.commit()
    } catch {
      store.reset()
      throw error
    }
    return SchedulingReceipt(eventCreated: true, reminderCreated: true)
  }

  private func requireAccess(to entity: EKEntityType) async throws {
    let status = EKEventStore.authorizationStatus(for: entity)
    let granted =
      if entity == .event {
        EventKitPermissionGate.calendarNeedsRequest(status: status)
          ? try await store.requestWriteOnlyAccessToEvents()
          : true
      } else {
        EventKitPermissionGate.remindersNeedRequest(status: status)
          ? try await store.requestFullAccessToReminders()
          : true
      }
    guard !granted else { return }
    throw entity == .event
      ? SchedulingError.calendarPermissionDenied
      : SchedulingError.remindersPermissionDenied
  }

  public enum SchedulingError: LocalizedError {
    case calendarPermissionDenied
    case remindersPermissionDenied
    case noReminderCalendar

    public var requiresPrivacySettings: Bool {
      switch self {
      case .calendarPermissionDenied, .remindersPermissionDenied:
        true
      case .noReminderCalendar:
        false
      }
    }

    public var errorDescription: String? {
      switch self {
      case .calendarPermissionDenied:
        "Calendar access is required to save this meeting."
      case .remindersPermissionDenied:
        "Reminders access is required to save this meeting."
      case .noReminderCalendar:
        "No writable reminder list is available."
      }
    }
  }
}

enum EventKitPermissionGate {
  static func calendarNeedsRequest(status: EKAuthorizationStatus) -> Bool {
    switch status {
    case .fullAccess, .authorized, .writeOnly:
      false
    case .notDetermined, .denied, .restricted:
      true
    @unknown default:
      true
    }
  }

  static func remindersNeedRequest(status: EKAuthorizationStatus) -> Bool {
    switch status {
    case .fullAccess, .authorized:
      false
    case .notDetermined, .denied, .restricted, .writeOnly:
      true
    @unknown default:
      true
    }
  }
}
