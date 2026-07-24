import Foundation
import FoundationModels
import ZoidZeroCore

public protocol OnDeviceActivityClassifying: Sendable {
  func classify(_ metadata: ActivityMetadata) async throws -> ActivityCategory?
}

public struct LocalActivityClassifier: Sendable {
  private let deterministic: DeterministicActivityClassifier
  private let model: (any OnDeviceActivityClassifying)?

  public init(
    deterministic: DeterministicActivityClassifier = .init(),
    model: (any OnDeviceActivityClassifying)? = FoundationModelsActivityClassifier()
  ) {
    self.deterministic = deterministic
    self.model = model
  }

  public func classify(_ metadata: ActivityMetadata) async -> ActivityCategory {
    if let category = deterministic.classify(
      metadata.subject,
      displayName: metadata.displayName
    ) {
      return category
    }
    guard let model else { return .uncategorized }
    return (try? await model.classify(metadata)) ?? .uncategorized
  }
}

public actor AutomaticActivityCategorizer {
  private let store: any AutomaticCategoryStoring
  private let classifier: LocalActivityClassifier

  public init(
    store: any AutomaticCategoryStoring,
    classifier: LocalActivityClassifier = .init()
  ) {
    self.store = store
    self.classifier = classifier
  }

  public func backfill() async {
    await categorize(await store.observedActivityMetadata())
  }

  public func categorize(_ metadataValues: [ActivityMetadata]) async {
    let manual = await store.userCategoryAssignments()
    let automatic = await store.automaticCategoryAssignments()
    let uniqueMetadata = Dictionary(
      metadataValues.map { ($0.subject, $0) },
      uniquingKeysWith: { _, newest in newest }
    )
    for metadata in uniqueMetadata.values
    where manual[metadata.subject] == nil && automatic[metadata.subject] == nil {
      let category = await classifier.classify(metadata)
      await store.setAutomaticCategory(category, for: metadata.subject)
    }
  }

  public func reset(_ metadata: ActivityMetadata) async {
    let category = await classifier.classify(metadata)
    await store.setAutomaticCategory(category, for: metadata.subject)
  }
}

public struct FoundationModelsActivityClassifier: OnDeviceActivityClassifying {
  public init() {}

  public func classify(_ metadata: ActivityMetadata) async throws -> ActivityCategory? {
    let model = SystemLanguageModel.default
    guard model.availability == .available else { return nil }
    let session = LanguageModelSession(
      model: model,
      tools: [],
      instructions: """
        Categorize one application or website using only the supplied stable metadata.
        Use exactly one of: work, communication, social, gaming, media, utilities, browser, uncategorized.
        Be conservative. Use uncategorized unless confidence is at least 0.85.
        Do not infer or request any private content.
        """
    )
    let response = try await session.respond(
      to: prompt(for: metadata),
      generating: GeneratedActivityCategory.self
    )
    guard response.content.confidence >= 0.85 else { return nil }
    return ActivityCategory(rawValue: response.content.category)
  }

  private func prompt(for metadata: ActivityMetadata) -> String {
    switch metadata.subject {
    case .application(let bundleIdentifier):
      return "Application bundle ID: \(bundleIdentifier)\nLocalized name: \(metadata.displayName)"
    case .website(let domain):
      return "Registrable website domain: \(domain)"
    }
  }
}

@Generable
private struct GeneratedActivityCategory {
  @Guide(
    description:
      "One category: work, communication, social, gaming, media, utilities, browser, uncategorized"
  )
  var category: String

  @Guide(description: "Confidence from zero to one", .range(0...1))
  var confidence: Double
}
