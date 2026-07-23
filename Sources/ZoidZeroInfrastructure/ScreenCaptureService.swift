import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import ZoidZeroCore

public enum ScreenRecordingPermissionState: Equatable, Sendable {
  case granted
  case denied
}

public struct ScreenRecordingPermissionController: @unchecked Sendable {
  private let defaults: UserDefaults
  private let preflight: @Sendable () -> Bool
  private let request: @Sendable () -> Bool
  private let requestKey = "didRequestScreenRecordingPermission"

  public init(
    defaults: UserDefaults = .standard,
    preflight: @escaping @Sendable () -> Bool = {
      CGPreflightScreenCaptureAccess()
    },
    request: @escaping @Sendable () -> Bool = {
      CGRequestScreenCaptureAccess()
    }
  ) {
    self.defaults = defaults
    self.preflight = preflight
    self.request = request
  }

  public func resolve() -> ScreenRecordingPermissionState {
    if preflight() {
      return .granted
    }
    guard !defaults.bool(forKey: requestKey) else {
      return .denied
    }
    defaults.set(true, forKey: requestKey)
    return request() ? .granted : .denied
  }
}

public enum ScreenFingerprintBuilder {
  public static func make(
    from image: CGImage,
    width: Int = 16,
    height: Int = 9
  ) throws -> VisualFingerprint {
    var pixels = [UInt8](repeating: 0, count: width * height)
    let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else { return false }
      context.interpolationQuality = .low
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered else {
      throw ScreenCaptureError.cannotCreateFingerprint
    }
    return VisualFingerprint(bytes: pixels)
  }
}

public protocol ScreenCaptureControlling: Sendable {
  func start() async
  func stop() async
}

public actor ScreenCaptureService: ScreenCaptureControlling {
  public struct Configuration: Sendable {
    public let samplingInterval: Duration
    public let idleThreshold: TimeInterval

    public init(
      samplingInterval: Duration = .seconds(5),
      idleThreshold: TimeInterval = 90
    ) {
      self.samplingInterval = samplingInterval
      self.idleThreshold = idleThreshold
    }
  }

  public typealias HealthHandler =
    @Sendable (
      CaptureHealthState
    ) async -> Void

  private let configuration: Configuration
  private let permission: ScreenRecordingPermissionController
  private let pipeline: ChangedScreenPipeline
  private let healthHandler: HealthHandler
  private let idleDetector = UserInputIdleDetector()
  private var captureTask: Task<Void, Never>?

  public init(
    configuration: Configuration = .init(),
    permission: ScreenRecordingPermissionController = .init(),
    pipeline: ChangedScreenPipeline,
    healthHandler: @escaping HealthHandler = { _ in }
  ) {
    self.configuration = configuration
    self.permission = permission
    self.pipeline = pipeline
    self.healthHandler = healthHandler
  }

  public func start() async {
    guard captureTask == nil else { return }
    if permission.resolve() == .denied {
      await healthHandler(.screenRecordingPermissionNeeded)
    }
    captureTask = Task { await self.runCaptureLoop() }
  }

  public func stop() async {
    let task = captureTask
    task?.cancel()
    await task?.value
    captureTask = nil
    await pipeline.cancel()
  }

  private func runCaptureLoop() async {
    var wasUnavailable = true
    while !Task.isCancelled {
      guard CGPreflightScreenCaptureAccess() else {
        wasUnavailable = true
        await healthHandler(.screenRecordingPermissionNeeded)
        try? await Task.sleep(for: configuration.samplingInterval)
        continue
      }
      let idleSeconds = idleDetector.idleDuration()
      if idleSeconds >= configuration.idleThreshold {
        wasUnavailable = true
        await healthHandler(.pausedWhileIdle)
      } else {
        do {
          if wasUnavailable {
            await healthHandler(.monitoring)
            wasUnavailable = false
          }
          try await captureChangedScreen()
        } catch is CancellationError {
          break
        } catch {
          wasUnavailable = true
          await healthHandler(.captureError(error.localizedDescription))
        }
      }
      try? await Task.sleep(for: configuration.samplingInterval)
    }
  }

  private func captureChangedScreen() async throws {
    guard CGPreflightScreenCaptureAccess() else {
      throw ScreenCaptureError.permissionDenied
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    let activeDisplayID = await MainActor.run {
      let mouse = NSEvent.mouseLocation
      let screen =
        NSScreen.screens.first { $0.frame.contains(mouse) }
        ?? NSScreen.main
      return screen?.deviceDescription[
        NSDeviceDescriptionKey("NSScreenNumber")
      ] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
    guard
      let display = content.displays.first(where: {
        $0.displayID == activeDisplayID
      }) ?? content.displays.first
    else {
      throw ScreenCaptureError.noDisplay
    }
    let activeApplication = await MainActor.run {
      let application = NSWorkspace.shared.frontmostApplication
      return (
        application?.localizedName ?? "Unknown",
        application?.processIdentifier
      )
    }
    let title =
      content.windows.first {
        $0.owningApplication?.processID == activeApplication.1
          && $0.isOnScreen
          && $0.windowLayer == 0
      }?.title ?? ""
    let streamConfiguration = SCStreamConfiguration()
    streamConfiguration.width = display.width
    streamConfiguration.height = display.height
    streamConfiguration.showsCursor = true
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: SCContentFilter(display: display, excludingWindows: []),
      configuration: streamConfiguration
    )
    let observedAt = Date()
    let fingerprint = try ScreenFingerprintBuilder.make(from: image)
    await pipeline.submit(
      CapturedScreen(
        id: "\(Int(observedAt.timeIntervalSince1970 * 1_000))",
        observedAt: observedAt,
        applicationName: activeApplication.0,
        windowTitle: title,
        fingerprint: fingerprint,
        image: image
      )
    )
  }
}

public enum ScreenCaptureError: LocalizedError {
  case permissionDenied
  case noDisplay
  case cannotCreateFingerprint

  public var errorDescription: String? {
    switch self {
    case .permissionDenied:
      "Screen Recording permission is required."
    case .noDisplay:
      "No active display is available for capture."
    case .cannotCreateFingerprint:
      "The changed-screen fingerprint could not be created."
    }
  }
}
