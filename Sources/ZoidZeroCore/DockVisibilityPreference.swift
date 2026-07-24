import Foundation

public struct DockVisibilityPreference {
  public static let key = "showZoidZeroInDock"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var showsInDock: Bool {
    guard defaults.object(forKey: Self.key) != nil else { return true }
    return defaults.bool(forKey: Self.key)
  }

  public func setShowsInDock(_ showsInDock: Bool) {
    defaults.set(showsInDock, forKey: Self.key)
  }
}
