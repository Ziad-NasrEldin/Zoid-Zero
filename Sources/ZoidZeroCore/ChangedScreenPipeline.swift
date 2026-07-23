import Foundation

public actor ChangedScreenPipeline {
  public struct Configuration: Sendable {
    public let debounce: Duration
    public let minimumOCRInterval: Duration
    public let visualDifferenceThreshold: Double

    public init(
      debounce: Duration = .milliseconds(700),
      minimumOCRInterval: Duration = .seconds(15),
      visualDifferenceThreshold: Double = 8
    ) {
      self.debounce = debounce
      self.minimumOCRInterval = minimumOCRInterval
      self.visualDifferenceThreshold = visualDifferenceThreshold
    }
  }

  public typealias Analyzer =
    @Sendable (
      CapturedScreen
    ) async throws -> ScreenAnalysisResult
  public typealias ResultHandler =
    @Sendable (
      ScreenAnalysisResult
    ) async -> Void
  public typealias HealthHandler =
    @Sendable (
      CaptureHealthState
    ) async -> Void

  private let configuration: Configuration
  private let now: @Sendable () async -> Date
  private let sleep: @Sendable (Duration) async -> Void
  private let analyzer: Analyzer
  private let resultHandler: ResultHandler
  private let healthHandler: HealthHandler
  private var lastFingerprint: VisualFingerprint?
  private var lastOCRStartedAt: Date?
  private var latestPending: CapturedScreen?
  private var workerTask: Task<Void, Never>?

  public init(
    configuration: Configuration = .init(),
    now: @escaping @Sendable () async -> Date = { Date() },
    sleep: @escaping @Sendable (Duration) async -> Void = {
      try? await Task.sleep(for: $0)
    },
    analyzer: @escaping Analyzer,
    resultHandler: @escaping ResultHandler = { _ in },
    healthHandler: @escaping HealthHandler = { _ in }
  ) {
    self.configuration = configuration
    self.now = now
    self.sleep = sleep
    self.analyzer = analyzer
    self.resultHandler = resultHandler
    self.healthHandler = healthHandler
  }

  public func submit(_ screen: CapturedScreen) {
    if let lastFingerprint,
      !screen.fingerprint.isMeaningfullyDifferent(
        from: lastFingerprint,
        threshold: configuration.visualDifferenceThreshold
      )
    {
      return
    }
    lastFingerprint = screen.fingerprint
    latestPending = screen
    guard workerTask == nil else { return }
    workerTask = Task { await self.processPendingScreens() }
  }

  public func finishCurrentWork() async {
    while let workerTask {
      await workerTask.value
    }
  }

  public func cancel() async {
    let task = workerTask
    task?.cancel()
    latestPending = nil
    await task?.value
    workerTask = nil
  }

  private func processPendingScreens() async {
    while !Task.isCancelled, var screen = latestPending {
      latestPending = nil
      if configuration.debounce > .zero {
        await sleep(configuration.debounce)
      }
      if let newer = latestPending {
        screen = newer
        latestPending = nil
      }
      guard !Task.isCancelled else { break }
      await waitForOCRCadence()
      guard !Task.isCancelled else { break }
      lastOCRStartedAt = await now()
      await healthHandler(.analyzingChangedScreen)
      do {
        let result = try await analyzer(screen)
        await resultHandler(result)
      } catch {
        await healthHandler(.captureError(error.localizedDescription))
      }
      if latestPending == nil {
        await healthHandler(.monitoring)
      }
    }
    workerTask = nil
  }

  private func waitForOCRCadence() async {
    guard let lastOCRStartedAt else { return }
    let elapsed = await now().timeIntervalSince(lastOCRStartedAt)
    let minimum = configuration.minimumOCRInterval.timeInterval
    if elapsed < minimum {
      await sleep(.seconds(minimum - elapsed))
    }
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let components = self.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1e18
  }
}
