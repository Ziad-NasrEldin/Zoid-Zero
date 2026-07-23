import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZoidZeroCore

public actor ScreenCaptureStorage {
  public static let defaultDaysRoot = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
  ).first!
  .appendingPathComponent("ZoidZero", isDirectory: true)
  .appendingPathComponent("Screenwatch", isDirectory: true)
  .appendingPathComponent("days", isDirectory: true)

  private let daysRoot: URL

  public init(daysRoot: URL = ScreenCaptureStorage.defaultDaysRoot) {
    self.daysRoot = daysRoot
  }

  @discardableResult
  public func persistAnalyzedScreen(
    _ result: ScreenAnalysisResult
  ) throws -> URL {
    let dayDirectory = daysRoot.appendingPathComponent(
      Self.dayFormatter.string(from: result.screen.observedAt),
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: dayDirectory,
      withIntermediateDirectories: true
    )
    let timeLabel = Self.timeFormatter.string(from: result.screen.observedAt)
    let imageURL = dayDirectory.appendingPathComponent("\(timeLabel).jpg")
    try Self.writeJPEG(result.screen.image, to: imageURL)
    do {
      try appendMetadata(
        result,
        timeLabel: timeLabel,
        to: dayDirectory.appendingPathComponent("log.jsonl")
      )
    } catch {
      try? FileManager.default.removeItem(at: imageURL)
      throw error
    }
    return imageURL
  }

  private func appendMetadata(
    _ result: ScreenAnalysisResult,
    timeLabel: String,
    to logURL: URL
  ) throws {
    let record: [String: Any] = [
      "t": timeLabel,
      "epoch": Int(result.screen.observedAt.timeIntervalSince1970),
      "app": result.screen.applicationName,
      "window": result.screen.windowTitle,
      "url": "",
      "img": true,
      "ocr": result.recognizedText,
    ]
    var data = try JSONSerialization.data(
      withJSONObject: record,
      options: [.sortedKeys]
    )
    data.append(0x0A)
    if !FileManager.default.fileExists(atPath: logURL.path) {
      guard
        FileManager.default.createFile(
          atPath: logURL.path,
          contents: nil
        )
      else {
        throw StorageError.cannotWriteMetadata
      }
    }
    let handle = try FileHandle(forWritingTo: logURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.synchronize()
  }

  private static func writeJPEG(_ image: CGImage, to url: URL) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      throw StorageError.cannotWriteScreenshot
    }
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: 0.76] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      throw StorageError.cannotWriteScreenshot
    }
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH-mm-ss-SSS"
    return formatter
  }()

  public enum StorageError: LocalizedError {
    case cannotWriteScreenshot
    case cannotWriteMetadata

    public var errorDescription: String? {
      switch self {
      case .cannotWriteScreenshot:
        "The analyzed screenshot could not be retained."
      case .cannotWriteMetadata:
        "The Screenwatch metadata record could not be written."
      }
    }
  }
}
