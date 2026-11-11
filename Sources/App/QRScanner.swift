import SwiftUI
import VisionKit

/// QR-Code mit der Kamera lesen (z. B. „Untis Mobile“ aus WebUntis am Computer)
struct QRScanner: UIViewControllerRepresentable {
    let gefunden: (String) -> Void

    static var verfuegbar: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let v = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true)
        v.delegate = context.coordinator
        try? v.startScanning()
        return v
    }
    func updateUIViewController(_ v: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Koordinator { Koordinator(gefunden) }

    final class Koordinator: NSObject, DataScannerViewControllerDelegate {
        let gefunden: (String) -> Void
        var fertig = false
        init(_ g: @escaping (String) -> Void) { gefunden = g }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fertig else { return }
            for i in items {
                if case .barcode(let b) = i, let text = b.payloadStringValue {
                    fertig = true
                    s.stopScanning()
                    gefunden(text)
                    return
                }
            }
        }
    }
}
