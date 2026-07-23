import AppKit
import CoreGraphics
import Foundation
import Vision

public protocol TextRecognizing: Sendable {
  func recognizeText(in image: CGImage) async throws -> String
}

public struct VisionTextRecognizer: TextRecognizing {
  public init() {}

  public func recognizeText(in image: CGImage) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        let text =
          (request.results as? [VNRecognizedTextObservation])?
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n") ?? ""
        continuation.resume(returning: text)
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      do {
        request.recognitionLanguages = Self.preferredLanguages(
          supported: try request.supportedRecognitionLanguages()
        )
      } catch {
        continuation.resume(throwing: error)
        return
      }
      do {
        try VNImageRequestHandler(cgImage: image).perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  public static func preferredLanguages(supported: [String]) -> [String] {
    let english =
      supported.first { $0 == "en-US" }
      ?? supported.first { $0.hasPrefix("en-") }
    let arabic =
      supported.first { $0 == "ar-SA" }
      ?? supported.first { $0.hasPrefix("ar-") || $0 == "ar" }
    let preferred = [english, arabic].compactMap { $0 }
    return preferred.isEmpty ? Array(supported.prefix(1)) : preferred
  }

  public enum RecognitionError: Error {
    case unreadableImage
  }
}
