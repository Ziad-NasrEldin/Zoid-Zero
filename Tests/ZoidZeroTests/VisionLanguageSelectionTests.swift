import Testing

@testable import ZoidZeroInfrastructure

@Suite("Vision recognition language selection")
struct VisionLanguageSelectionTests {
  @Test("supported English and Arabic languages are enabled")
  func englishAndArabicAreSelected() {
    #expect(
      VisionTextRecognizer.preferredLanguages(
        supported: ["fr-FR", "ar-SA", "en-US"]
      ) == ["en-US", "ar-SA"]
    )
  }

  @Test("unsupported Arabic is not assumed")
  func unsupportedArabicIsExcluded() {
    #expect(
      VisionTextRecognizer.preferredLanguages(
        supported: ["en-GB", "fr-FR"]
      ) == ["en-GB"]
    )
  }

  @Test("runtime list is preserved as a safe fallback")
  func runtimeListProvidesFallback() {
    #expect(
      VisionTextRecognizer.preferredLanguages(
        supported: ["de-DE", "fr-FR"]
      ) == ["de-DE"]
    )
  }
}
