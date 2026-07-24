import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Automatic local activity categorization")
struct AutomaticActivityCategorizationTests {
  @Test("deterministic result avoids the optional model")
  func deterministicResultAvoidsModel() async {
    let model = ModelClassifierSpy(result: .gaming)
    let classifier = LocalActivityClassifier(model: model)

    let category = await classifier.classify(
      ActivityMetadata(
        subject: .website(domain: "youtube.com"),
        displayName: "youtube.com"
      )
    )

    #expect(category == .media)
    #expect(await model.requestCount == 0)
  }

  @Test("available on-device model may classify an otherwise unknown item")
  func modelClassifiesUnknownItem() async {
    let classifier = LocalActivityClassifier(
      model: ModelClassifierSpy(result: .work)
    )

    let category = await classifier.classify(
      ActivityMetadata(
        subject: .application(bundleIdentifier: "com.example.editor"),
        displayName: "Acme Editor"
      )
    )

    #expect(category == .work)
  }

  @Test("model unavailability or failure keeps an unknown item uncategorized")
  func modelFailureIsSafe() async {
    let classifier = LocalActivityClassifier(
      model: ModelClassifierSpy(error: TestError.declined)
    )

    let category = await classifier.classify(
      ActivityMetadata(
        subject: .website(domain: "private.example"),
        displayName: "private.example"
      )
    )

    #expect(category == .uncategorized)
  }

  @Test("manual correction survives relaunch and reset restores automatic behavior")
  func manualCorrectionPersistsAndResets() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = root.appendingPathComponent("store.json")
    defer { try? FileManager.default.removeItem(at: root) }
    let subject = ActivitySubject.website(domain: "youtube.com")

    do {
      let store = ZoidLocalStore(fileURL: file)
      await store.setAutomaticCategory(.media, for: subject)
      await store.setCategory(.work, for: subject)
    }

    let relaunched = ZoidLocalStore(fileURL: file)
    #expect(await relaunched.userCategoryAssignments()[subject] == .work)
    #expect(await relaunched.automaticCategoryAssignments()[subject] == .media)

    await relaunched.resetCategory(for: subject)
    #expect(await relaunched.userCategoryAssignments()[subject] == nil)
    #expect(await relaunched.automaticCategoryAssignments()[subject] == .media)
  }

  @Test("backfill never overwrites a manual override")
  func backfillPreservesManualOverride() async {
    let store = CategorizationStoreSpy(
      metadata: [
        ActivityMetadata(
          subject: .website(domain: "youtube.com"),
          displayName: "youtube.com"
        )
      ],
      manual: [.website(domain: "youtube.com"): .work]
    )
    let automation = AutomaticActivityCategorizer(
      store: store,
      classifier: LocalActivityClassifier(model: nil)
    )

    await automation.backfill()

    #expect(await store.automaticAssignments.isEmpty)
    #expect(await store.manualAssignments[.website(domain: "youtube.com")] == .work)
  }

  @Test("metadata boundary contains no URL path or window title")
  func metadataBoundaryIsMinimal() {
    let website = ActivityMetadata(
      subject: .website(domain: "bank.example"),
      displayName: "bank.example"
    )
    let app = ActivityMetadata(
      subject: .application(bundleIdentifier: "com.example.private"),
      displayName: "Private App"
    )

    #expect(website.subject.stableIdentifier == "web:bank.example")
    #expect(website.displayName == "bank.example")
    #expect(app.subject.stableIdentifier == "app:com.example.private")
  }
}

private enum TestError: Error {
  case declined
}

private actor ModelClassifierSpy: OnDeviceActivityClassifying {
  private(set) var requestCount = 0
  private let result: ActivityCategory?
  private let error: Error?

  init(result: ActivityCategory? = nil, error: Error? = nil) {
    self.result = result
    self.error = error
  }

  func classify(_ metadata: ActivityMetadata) async throws -> ActivityCategory? {
    requestCount += 1
    if let error { throw error }
    return result
  }
}

private actor CategorizationStoreSpy: AutomaticCategoryStoring {
  private let metadata: [ActivityMetadata]
  private(set) var manualAssignments: [ActivitySubject: ActivityCategory]
  private(set) var automaticAssignments: [ActivitySubject: ActivityCategory] = [:]

  init(
    metadata: [ActivityMetadata],
    manual: [ActivitySubject: ActivityCategory] = [:]
  ) {
    self.metadata = metadata
    manualAssignments = manual
  }

  func setAutomaticCategory(_ category: ActivityCategory, for subject: ActivitySubject) {
    automaticAssignments[subject] = category
  }

  func automaticCategoryAssignments() -> [ActivitySubject: ActivityCategory] {
    automaticAssignments
  }

  func userCategoryAssignments() -> [ActivitySubject: ActivityCategory] {
    manualAssignments
  }

  func observedActivityMetadata() -> [ActivityMetadata] {
    metadata
  }
}
