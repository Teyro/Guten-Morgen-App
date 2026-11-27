import SwiftUI
import WidgetKit

/// Nur für die Bildschirmfotos in der CI (GM_ANSICHT=widget): das Haupt-Widget in seinen Größen mit Beispieldaten
struct WidgetGalerie: View {
    var farbton = "system"
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) { feld(.systemSmall, 158, 158); feld(.systemSmall, 158, 158, farbton: "ozean") }
                feld(.systemMedium, 338, 158)
                feld(.systemLarge, 338, 354)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(red: 0.55, green: 0.7, blue: 0.95), Color(red: 0.95, green: 0.7, blue: 0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func feld(_ f: WidgetFamily, _ b: CGFloat, _ h: CGFloat, farbton: String? = nil) -> some View {
        var e = MorgenEintrag.beispiel
        e.farbton = farbton ?? self.farbton
        return MorgenWidgetAnsicht(e: e, familieVorgabe: f)
            .padding(16)
            .frame(width: b, height: h)
            .background(WidgetGrund(farbton: Farbton.zu(e.farbton)))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
