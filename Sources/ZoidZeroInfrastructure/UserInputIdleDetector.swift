import CoreGraphics
import Foundation

public struct UserInputIdleDetector: Sendable {
  private static let activityEventTypes: [CGEventType] = [
    .leftMouseDown,
    .leftMouseUp,
    .rightMouseDown,
    .rightMouseUp,
    .mouseMoved,
    .leftMouseDragged,
    .rightMouseDragged,
    .keyDown,
    .keyUp,
    .flagsChanged,
    .scrollWheel,
    .tabletPointer,
    .tabletProximity,
    .otherMouseDown,
    .otherMouseUp,
    .otherMouseDragged,
  ]

  private let secondsSinceLastEvent: @Sendable (CGEventType) -> TimeInterval

  public init(
    secondsSinceLastEvent: @escaping @Sendable (CGEventType) -> TimeInterval = {
      CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: $0
      )
    }
  ) {
    self.secondsSinceLastEvent = secondsSinceLastEvent
  }

  public func idleDuration() -> TimeInterval {
    Self.activityEventTypes
      .map(secondsSinceLastEvent)
      .min() ?? .infinity
  }
}
