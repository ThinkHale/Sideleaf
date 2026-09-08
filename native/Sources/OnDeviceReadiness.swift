import Speech
import Observation
import Foundation

@MainActor @Observable
final class OnDeviceReadiness {
    private(set) var message = "Checking device and language support…"
    private(set) var needsAssets = false
    private var locale: Locale?

    func check() async {
        needsAssets = false
        guard SpeechTranscriber.isAvailable else { message = "This device does not support SpeechTranscriber. Remote audio will not be used as a fallback."; return }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { message = "On-device transcription is unavailable for this language. Remote audio will not be used as a fallback."; return }
        locale = supported
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier == supported.identifier }) { message = "On-device language assets are installed. Live capture still needs integration and hardware verification." }
        else { needsAssets = true; message = "Download the on-device language assets before a meeting. This requires a network connection." }
    }
    func installAssets() async {
        guard let locale else { return }
        do {
            message = "Downloading language assets…"
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
            await check()
        } catch { message = "Language assets could not be installed. Try again before the meeting." }
    }
}
