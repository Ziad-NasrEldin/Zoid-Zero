import Foundation
import Testing
@testable import ZoidZeroCore

@Suite("Dock visibility preference")
struct DockVisibilityPreferenceTests {
  @Test("existing users keep the Dock icon by default")
  func defaultsToVisible() {
    let defaults = isolatedDefaults()
    let preference = DockVisibilityPreference(defaults: defaults)

    #expect(preference.showsInDock)
  }

  @Test("hidden preference persists across controller instances")
  func hiddenPreferencePersists() {
    let defaults = isolatedDefaults()
    DockVisibilityPreference(defaults: defaults).setShowsInDock(false)

    #expect(!DockVisibilityPreference(defaults: defaults).showsInDock)
  }

  @Test("restoring the Dock icon persists")
  func visiblePreferencePersists() {
    let defaults = isolatedDefaults()
    let preference = DockVisibilityPreference(defaults: defaults)
    preference.setShowsInDock(false)
    preference.setShowsInDock(true)

    #expect(DockVisibilityPreference(defaults: defaults).showsInDock)
  }

  private func isolatedDefaults() -> UserDefaults {
    let suiteName = "DockVisibilityPreferenceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
