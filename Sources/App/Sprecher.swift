import AVFoundation

/// Vorlesen mit der deutschen Systemstimme
@MainActor
final class Sprecher: NSObject {
    static let shared = Sprecher()
    private let synth = AVSpeechSynthesizer()

    func sprechen(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "de-DE")
        u.rate = 0.5
        synth.speak(u)
    }
    func stopp() { synth.stopSpeaking(at: .immediate) }
    var spricht: Bool { synth.isSpeaking }
}
