import CoreGraphics
import Foundation
import Testing

@testable import ZoidZeroCore

@Suite("Changed screen pipeline")
struct ChangedScreenPipelineTests {
  @Test("unchanged screens never run OCR")
  func unchangedScreensSkipOCR() async throws {
    let analyzer = AnalysisRecorder()
    let pipeline = ChangedScreenPipeline(
      configuration: .init(debounce: .zero, minimumOCRInterval: .zero),
      analyzer: analyzer.analyze
    )

    await pipeline.submit(screen(id: "one", fingerprint: [10, 20]))
    await pipeline.submit(screen(id: "two", fingerprint: [10, 20]))
    await pipeline.finishCurrentWork()

    #expect(await analyzer.ids == ["one"])
  }

  @Test("every application source can be analyzed")
  func everyApplicationCanBeAnalyzed() async {
    let analyzer = AnalysisRecorder()
    let pipeline = ChangedScreenPipeline(
      configuration: .init(debounce: .zero, minimumOCRInterval: .zero),
      analyzer: analyzer.analyze
    )

    await pipeline.submit(
      screen(
        id: "xcode",
        fingerprint: [1],
        applicationName: "Xcode"
      )
    )
    await pipeline.finishCurrentWork()

    #expect(await analyzer.applications == ["Xcode"])
  }

  @Test("busy OCR retains only the newest queued changed screen")
  func busyOCRRetainsNewestScreen() async {
    let analyzer = BlockingAnalysisRecorder()
    let pipeline = ChangedScreenPipeline(
      configuration: .init(debounce: .zero, minimumOCRInterval: .zero),
      analyzer: analyzer.analyze
    )

    await pipeline.submit(screen(id: "one", fingerprint: [1]))
    await analyzer.waitUntilFirstAnalysisStarts()
    await pipeline.submit(screen(id: "two", fingerprint: [20]))
    await pipeline.submit(screen(id: "three", fingerprint: [40]))
    await analyzer.releaseFirstAnalysis()
    await pipeline.finishCurrentWork()

    #expect(await analyzer.ids == ["one", "three"])
  }

  @Test("OCR starts are separated by the configured minimum interval")
  func ocrCadenceIsRateLimited() async {
    let clock = PipelineClock(start: Date(timeIntervalSince1970: 100))
    let analyzer = AnalysisRecorder(clock: clock)
    let pipeline = ChangedScreenPipeline(
      configuration: .init(
        debounce: .zero,
        minimumOCRInterval: .seconds(15)
      ),
      now: { await clock.now() },
      sleep: { await clock.sleep($0) },
      analyzer: analyzer.analyze
    )

    await pipeline.submit(screen(id: "one", fingerprint: [1]))
    await pipeline.finishCurrentWork()
    await pipeline.submit(screen(id: "two", fingerprint: [30]))
    await pipeline.finishCurrentWork()

    let starts = await analyzer.startDates
    #expect(starts.count == 2)
    #expect(starts[1].timeIntervalSince(starts[0]) >= 15)
  }
}

private actor AnalysisRecorder {
  private(set) var ids: [String] = []
  private(set) var applications: [String] = []
  private(set) var startDates: [Date] = []
  private let clock: PipelineClock?

  init(clock: PipelineClock? = nil) {
    self.clock = clock
  }

  func analyze(_ screen: CapturedScreen) async throws -> ScreenAnalysisResult {
    ids.append(screen.id)
    applications.append(screen.applicationName)
    if let clock {
      startDates.append(await clock.now())
    }
    return ScreenAnalysisResult(screen: screen, recognizedText: "", candidates: [])
  }
}

private actor BlockingAnalysisRecorder {
  private(set) var ids: [String] = []
  private var started = false
  private var released = false

  func analyze(_ screen: CapturedScreen) async throws -> ScreenAnalysisResult {
    ids.append(screen.id)
    if ids.count == 1 {
      started = true
      while !released {
        await Task.yield()
      }
    }
    return ScreenAnalysisResult(screen: screen, recognizedText: "", candidates: [])
  }

  func waitUntilFirstAnalysisStarts() async {
    while !started {
      await Task.yield()
    }
  }

  func releaseFirstAnalysis() {
    released = true
  }
}

private actor PipelineClock {
  private var date: Date

  init(start: Date) {
    date = start
  }

  func now() -> Date {
    date
  }

  func sleep(_ duration: Duration) {
    date = date.addingTimeInterval(duration.timeInterval)
  }
}

private func screen(
  id: String,
  fingerprint: [UInt8],
  applicationName: String = "Any App"
) -> CapturedScreen {
  CapturedScreen(
    id: id,
    observedAt: Date(timeIntervalSince1970: 1_753_200_000),
    applicationName: applicationName,
    windowTitle: "",
    fingerprint: VisualFingerprint(bytes: fingerprint),
    image: onePixelImage()
  )
}

private func onePixelImage() -> CGImage {
  let bytes: [UInt8] = [255, 255, 255, 255]
  let provider = CGDataProvider(data: Data(bytes) as CFData)!
  return CGImage(
    width: 1,
    height: 1,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
  )!
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let components = self.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1e18
  }
}
