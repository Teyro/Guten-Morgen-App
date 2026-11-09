import AVFoundation
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers
import MorgenKern

/// Weckmusik im Nachtmodus: Die App bleibt (mit einer stillen Tonspur) wach, spielt zur Weckzeit einen Titel aus
/// der Apple-Music-Mediathek oder eine eigene Datei und blendet die Lautstärke langsam ein.
@MainActor
@Observable
final class Weckmusik {
    enum Quelle: String, Codable, CaseIterable { case aus, apple, datei }

    var quelle: Quelle { didSet { UserDefaults.standard.set(quelle.rawValue, forKey: "musikQuelle") } }
    var titel: String { didSet { UserDefaults.standard.set(titel, forKey: "musikTitel") } }
    var einblendenSek: Int { didSet { UserDefaults.standard.set(einblendenSek, forKey: "musikEinblenden") } }
    var zielLautstaerke: Double { didSet { UserDefaults.standard.set(zielLautstaerke, forKey: "musikLautstaerke") } }
    private var appleID: UInt64 { didSet { UserDefaults.standard.set(String(appleID), forKey: "musikAppleID") } }

    var klingelt = false
    @ObservationIgnored private var still: AVAudioPlayer?
    @ObservationIgnored private var spieler: AVAudioPlayer?
    @ObservationIgnored private var weckTimer: Timer?
    @ObservationIgnored private var blendTimer: Timer?
    @ObservationIgnored private let lautstaerke = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))

    init() {
        let d = UserDefaults.standard
        quelle = Quelle(rawValue: d.string(forKey: "musikQuelle") ?? "") ?? .aus
        titel = d.string(forKey: "musikTitel") ?? ""
        einblendenSek = d.object(forKey: "musikEinblenden") as? Int ?? 60
        zielLautstaerke = d.object(forKey: "musikLautstaerke") as? Double ?? 0.6
        appleID = UInt64(d.string(forKey: "musikAppleID") ?? "") ?? 0
    }

    static var dateiURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("weckmusik")
    }

    // MARK: Auswahl

    func appleGewaehlt(_ item: MPMediaItem) {
        appleID = item.persistentID
        titel = [item.title, item.artist].compactMap { $0 }.joined(separator: " – ")
        quelle = .apple
    }

    func dateiGewaehlt(_ url: URL) -> Bool {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: Weckmusik.dateiURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: Weckmusik.dateiURL)
            try FileManager.default.copyItem(at: url, to: Weckmusik.dateiURL)
            titel = url.deletingPathExtension().lastPathComponent
            quelle = .datei
            return true
        } catch { return false }
    }

    // MARK: Nachtmodus

    /// Wach bleiben bis [weckzeit], dann klingeln
    func nachtBeginnen(weckzeit: Date) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        // stille Tonspur hält die App im Hintergrund am Leben (wie bei Wecker-Apps üblich)
        still = try? AVAudioPlayer(data: Weckmusik.stilleWAV())
        still?.numberOfLoops = -1
        still?.volume = 0
        still?.play()
        weckTimer?.invalidate()
        let t = Timer(fire: weckzeit, interval: 0, repeats: false) { [weak self] _ in Task { @MainActor in self?.klingeln() } }
        RunLoop.main.add(t, forMode: .common)
        weckTimer = t
    }

    func nachtBeenden() {
        weckTimer?.invalidate(); weckTimer = nil
        blendTimer?.invalidate(); blendTimer = nil
        still?.stop(); still = nil
        spieler?.stop(); spieler = nil
        MPMusicPlayerController.applicationQueuePlayer.stop()
        klingelt = false
    }

    func klingeln() {
        klingelt = true
        setzeSystemLautstaerke(0.08)
        var laeuft = false
        switch quelle {
        case .apple:
            let q = MPMediaQuery.songs()
            q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: appleID), forProperty: MPMediaItemPropertyPersistentID))
            if let items = q.items, !items.isEmpty {
                let p = MPMusicPlayerController.applicationQueuePlayer
                p.setQueue(with: MPMediaItemCollection(items: items))
                p.repeatMode = .one
                p.play()
                laeuft = true
            }
        case .datei:
            if let s = try? AVAudioPlayer(contentsOf: Weckmusik.dateiURL) { s.numberOfLoops = -1; s.volume = 1; s.play(); spieler = s; laeuft = true }
        case .aus: break
        }
        if !laeuft, let s = try? AVAudioPlayer(data: Weckmusik.weckton()) { s.numberOfLoops = -1; s.play(); spieler = s }
        // langsam lauter: von 8 % bis zur Ziel-Lautstärke
        let start = Date()
        blendTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let anteil = min(1, Date().timeIntervalSince(start) / Double(max(5, self.einblendenSek)))
                self.setzeSystemLautstaerke(0.08 + (self.zielLautstaerke - 0.08) * anteil)
                if anteil >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        blendTimer = t
    }

    func schlummern(minuten: Int = 9) {
        spieler?.stop(); spieler = nil
        MPMusicPlayerController.applicationQueuePlayer.pause()
        blendTimer?.invalidate()
        klingelt = false
        nachtBeginnen(weckzeit: Date().addingTimeInterval(Double(minuten * 60)))
    }

    /// Lautstärke des iPhones setzen (über den System-Regler – anders lässt iOS das nicht zu)
    private func setzeSystemLautstaerke(_ wert: Double) {
        if let regler = lautstaerke.subviews.compactMap({ $0 as? UISlider }).first {
            regler.value = Float(min(1, max(0, wert)))
        }
    }

    // MARK: Töne

    /// 2 s Stille als WAV (8 kHz, 8 Bit)
    static func stilleWAV() -> Data { wav(sekunden: 2) { _ in 128 } }

    /// Sanfter Ersatz-Weckton, falls keine Musik gewählt ist (Dreiklang)
    static func weckton() -> Data {
        wav(sekunden: 3) { i in
            let t = Double(i) / 8000
            let teil = Int(t * 3) % 3
            let f = [523.25, 659.25, 783.99][teil]
            let huelle = max(0, 1 - (t * 3 - floor(t * 3)) * 1.2)
            return UInt8(128 + 60 * huelle * sin(2 * .pi * f * t))
        }
    }

    private static func wav(sekunden: Int, probe: (Int) -> UInt8) -> Data {
        let n = 8000 * sekunden
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + n); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(8000); u32(8000); u16(1); u16(8)
        d.append(contentsOf: Array("data".utf8)); u32(n)
        d.append(contentsOf: (0..<n).map(probe))
        return d
    }
}

/// Titel aus der Mediathek wählen (Apple Music, auch geladene Titel)
struct MediathekWahl: UIViewControllerRepresentable {
    let gewaehlt: (MPMediaItem) -> Void
    @Environment(\.dismiss) private var schliessen

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let p = MPMediaPickerController(mediaTypes: .music)
        p.allowsPickingMultipleItems = false
        p.showsCloudItems = true
        p.prompt = "Titel zum Wecken"
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}
    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, MPMediaPickerControllerDelegate {
        let eltern: MediathekWahl
        init(_ e: MediathekWahl) { eltern = e }
        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems c: MPMediaItemCollection) {
            if let i = c.items.first { eltern.gewaehlt(i) }
            mediaPicker.dismiss(animated: true)
        }
        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) { mediaPicker.dismiss(animated: true) }
    }
}

/// Nachtmodus: dunkle Uhr, Bildschirm bleibt an; zur Weckzeit Musik mit Einblenden
struct NachtAnsicht: View {
    let kern: Kern
    let musik: Weckmusik
    @Environment(\.dismiss) private var schliessen
    @State private var jetzt = Date()
    @State private var helligkeit: CGFloat = 0.5
    private let takt = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let w = kern.naechsterWecker
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(jetzt.uhrzeit).font(.system(size: 96, weight: .thin, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.3).opacity(0.8))
                if musik.klingelt {
                    Text("Guten Morgen!").font(.title.weight(.semibold)).foregroundStyle(.white)
                    HStack(spacing: 14) {
                        Button { musik.schlummern() } label: { GrosserKnopf(symbol: "zzz", titel: "9 Minuten", farbe: .gray) }
                        Button {
                            musik.nachtBeenden()
                            Task { await kern.nachtVorbei(); await kern.briefingVorlesen() }
                            schliessen()
                        } label: { GrosserKnopf(symbol: "sun.max.fill", titel: "Aufstehen", farbe: .orange) }
                    }
                    .buttonStyle(.plain)
                } else {
                    Label(w.minuten.map { "Wecker \(Zeit.hhmm($0)) · \(musik.quelle == .aus ? "Weckton" : musik.titel)" } ?? "kein Wecker", systemImage: "alarm")
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Nachtmodus beenden") { musik.nachtBeenden(); Task { await kern.nachtVorbei() }; schliessen() }
                        .foregroundStyle(.white.opacity(0.5)).padding(.top, 30)
                }
            }
            .padding()
        }
        .onReceive(takt) { jetzt = $0 }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            helligkeit = UIScreen.main.brightness
            UIScreen.main.brightness = 0.05
            if let d = w.datum { musik.nachtBeginnen(weckzeit: d) }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            UIScreen.main.brightness = helligkeit
        }
        .onChange(of: musik.klingelt) { _, an in if an { UIScreen.main.brightness = 0.7 } }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
