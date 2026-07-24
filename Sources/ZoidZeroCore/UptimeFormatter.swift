import Foundation

public enum UptimeFormatter {
  public static func concise(from startDate: Date, now: Date = Date()) -> String {
    concise(elapsed: now.timeIntervalSince(startDate))
  }

  public static func concise(elapsed: TimeInterval) -> String {
    let elapsed = max(0, Int(elapsed))
    let totalMinutes = elapsed / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes / 60) % 24
    let minutes = totalMinutes % 60

    if days > 0 {
      return "\(days)d \(hours)h"
    }
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
  }
}
