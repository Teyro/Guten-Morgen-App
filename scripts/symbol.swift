// App-Symbol zeichnen: Sonne über dem Horizont auf Morgenrot-Verlauf („Guten Morgen“).
// Aufruf: swift scripts/symbol.swift <AppIcon-1024.png>
import AppKit
import ImageIO

let gross = CommandLine.arguments[1]

func bild(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let flaeche = NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s))
    NSGradient(colors: [NSColor(red: 0.18, green: 0.2, blue: 0.48, alpha: 1), NSColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1), NSColor(red: 1.0, green: 0.78, blue: 0.4, alpha: 1)])!
        .draw(in: flaeche, angle: -90)
    let sonne = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)]))
    if let sym = NSImage(systemSymbolName: "sunrise.fill", accessibilityDescription: nil)?.withSymbolConfiguration(sonne) {
        let g = sym.size
        sym.draw(in: NSRect(x: (s - g.width) / 2, y: (s - g.height) / 2, width: g.width, height: g.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let rgba = NSBitmapImageRep(data: bild(1024))!.cgImage!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(rgba, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let ziel = CGImageDestinationCreateWithURL(URL(fileURLWithPath: gross) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(ziel, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(ziel), "Symbol konnte nicht geschrieben werden")
