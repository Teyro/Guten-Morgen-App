import SwiftUI
import MorgenKern

/// Chat (Matrix/Element der Schule) – angemeldet mit den IServ-Zugangsdaten, aktuell gehalten per Long-Poll, solange der Chat offen ist.
@MainActor @Observable final class ChatModell {
    static let shared = ChatModell()
    var raeume: [Matrix.Raum] = []
    var fehler = ""
    var laedt = false
    private var matrix: Matrix?
    private var weiter = ""
    private var schleife: Task<Void, Never>?

    var ich: String { matrix?.ich ?? "" }
    var ungelesen: Int { raeume.reduce(0) { $0 + $1.ungelesen } }

    /// Anmelden (Token bleibt im Schlüsselbund) und Abrufe starten
    func start(_ kern: Kern) {
        guard schleife == nil else { return }
        schleife = Task {
            if matrix == nil, let s = Schluesselbund.lesen("matrix"), let tab = s.firstIndex(of: "\t") {
                matrix = Matrix(token: String(s[s.index(after: tab)...]), ich: String(s[..<tab]))
            }
            while !Task.isCancelled {
                do {
                    if matrix == nil {
                        let b = kern.einstellungen.iservBenutzer, p = kern.iservPasswort
                        guard !b.isEmpty, !p.isEmpty else { fehler = "Bitte zuerst IServ in den Einstellungen einrichten – der Chat nutzt dieselbe Anmeldung."; break }
                        laedt = true
                        let m = try await Matrix.anmelden(benutzer: b, passwort: p)
                        matrix = m; Schluesselbund.speichern(m.ich + "\t" + m.token, "matrix")
                    }
                    guard let m = matrix else { break }
                    laedt = raeume.isEmpty
                    let j = try await m.sync(seit: weiter, warten: weiter.isEmpty ? 0 : 25_000)
                    (raeume, weiter) = Matrix.einarbeiten(j, in: raeume)
                    fehler = ""; laedt = false
                } catch Matrix.Fehler.anmeldung where matrix != nil {
                    matrix = nil; weiter = ""; Schluesselbund.speichern("", "matrix") // Token abgelaufen → neu anmelden
                } catch is CancellationError { break
                } catch {
                    if (error as? URLError)?.code == .cancelled { break }
                    fehler = error.localizedDescription; laedt = false
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            laedt = false; schleife = nil
        }
    }

    func stop() { schleife?.cancel(); schleife = nil }

    func senden(_ text: String, an raum: String) async {
        guard let m = matrix else { return }
        do { try await m.senden(raum: raum, text: text) } catch { fehler = error.localizedDescription }
    }

    /// Anpinnen sofort zeigen, dann an den Server (Favorit wie in Element); bei Fehler zurück
    func anpinnen(_ r: Matrix.Raum) {
        guard let m = matrix, let i = raeume.firstIndex(where: { $0.id == r.id }) else { return }
        let an = !r.angepinnt
        raeume[i].angepinnt = an; raeume = Matrix.sortiert(raeume)
        Task {
            do { try await m.anpinnen(raum: r.id, an) } catch {
                fehler = error.localizedDescription
                if let j = raeume.firstIndex(where: { $0.id == r.id }) { raeume[j].angepinnt = !an; raeume = Matrix.sortiert(raeume) }
            }
        }
    }

    func gelesen(_ r: Matrix.Raum) {
        guard let m = matrix, let letzte = r.nachrichten.last, r.ungelesen > 0 else { return }
        if let i = raeume.firstIndex(where: { $0.id == r.id }) { raeume[i].ungelesen = 0 }
        Task { await m.gelesen(raum: r.id, event: letzte.id) }
    }
}

/// Liste der Chats wie in Nachrichten: rundes Bild, Name, letzte Nachricht, Zeit, blauer Punkt bei Ungelesenem
struct ChatListe: View {
    let kern: Kern
    @State private var chat = ChatModell.shared
    @State private var suche = ""

    var body: some View {
        List {
            if !chat.fehler.isEmpty { Label(chat.fehler, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            ForEach(Matrix.suchen(chat.raeume, suche)) { r in
                NavigationLink { ChatRaum(raumID: r.id) } label: { zeile(r) }
                    .swipeActions(edge: .leading) {
                        Button { chat.anpinnen(r) } label: { Label(r.angepinnt ? "Loslösen" : "Anpinnen", systemImage: r.angepinnt ? "pin.slash.fill" : "pin.fill") }.tint(.orange)
                    }
                    .contextMenu {
                        Button { chat.anpinnen(r) } label: { Label(r.angepinnt ? "Loslösen" : "Anpinnen", systemImage: r.angepinnt ? "pin.slash" : "pin") }
                    }
            }
        }
        .listStyle(.plain)
        .searchable(text: $suche, prompt: "Suchen")
        .animation(.snappy, value: chat.raeume.map(\.id))
        .overlay { if chat.laedt && chat.raeume.isEmpty { ProgressView("Chats laden …") } else if chat.raeume.isEmpty && chat.fehler.isEmpty { ContentUnavailableView("Keine Chats", systemImage: "bubble.left.and.bubble.right") } }
        .navigationTitle("Chat")
        .onAppear { chat.start(kern) }
    }

    private func zeile(_ r: Matrix.Raum) -> some View {
        HStack(spacing: 12) {
            Circle().fill(r.ungelesen > 0 ? Color.blue : .clear).frame(width: 9, height: 9)
            ChatBild(name: r.name, gross: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(r.name).font(.headline).lineLimit(1)
                    if r.angepinnt { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    if let l = r.nachrichten.last { Text(ChatRaum.zeitKurz(l.zeit)).font(.subheadline).foregroundStyle(.secondary) }
                }
                Text(r.nachrichten.last.map { (r.helden.count > 1 || !r.titel.isEmpty ? r.name(von: $0.absender).split(separator: " ").first.map { "\($0): " } ?? "" : "") + $0.text } ?? "")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Runder Kreis mit Initialen in Grautönen wie bei Kontakten ohne Foto
struct ChatBild: View {
    let name: String
    var gross = false
    var body: some View {
        let i = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Text(i.isEmpty ? "?" : i).font(gross ? .headline : .caption2.weight(.semibold)).foregroundStyle(.white)
            .frame(width: gross ? 48 : 28, height: gross ? 48 : 28)
            .background(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.52)], startPoint: .top, endPoint: .bottom), in: Circle())
    }
}

/// Ein Gespräch im Stil von iMessage: eigene Blasen blau rechts, andere grau links, gläserne Eingabeleiste unten
struct ChatRaum: View {
    let raumID: String
    @State private var chat = ChatModell.shared
    @State private var text = ""
    @FocusState private var tippt: Bool

    private var raum: Matrix.Raum? { chat.raeume.first { $0.id == raumID } }

    var body: some View {
        ScrollViewReader { leser in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if let r = raum {
                        let l = r.nachrichten
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, n in
                            let vorher = i > 0 ? l[i - 1] : nil, nachher = i + 1 < l.count ? l[i + 1] : nil
                            if vorher.map({ n.zeit.timeIntervalSince($0.zeit) > 3600 }) ?? true {
                                Text(Self.zeitLang(n.zeit)).font(.caption2).foregroundStyle(.secondary).padding(.top, 12).padding(.bottom, 4)
                            }
                            blase(n, raum: r, ersteVon: vorher?.absender != n.absender, letzteVon: nachher?.absender != n.absender).id(n.id)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: raum?.nachrichten.last?.id) { _, id in
                if let id { withAnimation { leser.scrollTo(id, anchor: .bottom) } }
                if let r = raum { chat.gelesen(r) }
            }
        }
        .safeAreaInset(edge: .bottom) { eingabe }
        .navigationTitle(raum?.name ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let r = raum { chat.gelesen(r) } }
    }

    private func blase(_ n: Matrix.Nachricht, raum r: Matrix.Raum, ersteVon: Bool, letzteVon: Bool) -> some View {
        let eigen = n.absender == chat.ich
        let gruppe = r.helden.count > 1 || !r.titel.isEmpty
        return HStack(alignment: .bottom, spacing: 6) {
            if eigen { Spacer(minLength: 60) }
            else if gruppe { ChatBild(name: r.name(von: n.absender)).opacity(letzteVon ? 1 : 0) }
            VStack(alignment: .leading, spacing: 2) {
                if gruppe && !eigen && ersteVon { Text(r.name(von: n.absender)).font(.caption).foregroundStyle(.secondary).padding(.leading, 12) }
                Text(n.text)
                    .italic(n.verschluesselt)
                    .foregroundStyle(eigen ? Color.white : Color.primary)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(eigen ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color(.systemGray5)), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .textSelection(.enabled)
            }
            if !eigen { Spacer(minLength: 60) }
        }
        .padding(.top, ersteVon ? 6 : 0)
    }

    private var eingabe: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(raum?.verschluesselt == true ? "Verschlüsselter Chat – nur in Element" : "Nachricht", text: $text, axis: .vertical)
                .lineLimit(1...5).focused($tippt)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glas(20)
                .disabled(raum?.verschluesselt == true)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines); text = ""
                    Task { await chat.senden(t, an: raumID) }
                } label: { Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(.white).frame(width: 36, height: 36) }
                .glasKnopf(.blue, 18)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: text.isEmpty)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    static func zeitKurz(_ d: Date) -> String {
        let k = Calendar.current
        if k.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if k.isDateInYesterday(d) { return "Gestern" }
        return d.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
    }
    static func zeitLang(_ d: Date) -> String {
        let k = Calendar.current
        let tag = k.isDateInToday(d) ? "Heute" : k.isDateInYesterday(d) ? "Gestern" : d.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return tag + " " + d.formatted(date: .omitted, time: .shortened)
    }
}
