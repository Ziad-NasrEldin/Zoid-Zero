import EventKit
import Testing

@testable import ZoidZeroInfrastructure

@Test("a cached Calendar denial still retries the system permission request")
func cachedCalendarDenialStillRequestsAccess() {
  #expect(EventKitPermissionGate.calendarNeedsRequest(status: .denied))
}

@Test("Calendar write-only access is sufficient to create an event")
func calendarWriteOnlyAccessDoesNotRequestAgain() {
  #expect(!EventKitPermissionGate.calendarNeedsRequest(status: .writeOnly))
}
