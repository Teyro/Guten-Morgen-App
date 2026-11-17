// App-Symbol „DammAPP“: die vier Stifte aus dem Schullogo auf einfarbigem Dunkelblau – ohne Rahmen, ohne Text.
// Aufruf (aus dem Repo-Ordner): swift scripts/symbol.swift <AppIcon-1024.png>   – Quelle: ressourcen/Stifte.png (freigestellt)
// Stifte auf 70 % Höhe: bleiben unter der runden Watch-Maske und den iPhone-Ecken ganz sichtbar.
// iOS-Symbole dürfen nicht durchsichtig sein – daher ohne Alphakanal.
import AppKit
import ImageIO

let gross = CommandLine.arguments[1]
guard let quelle = CGImageSourceCreateWithURL(URL(fileURLWithPath: "ressourcen/Stifte.png") as CFURL, nil),
      let stifte = CGImageSourceCreateImageAtIndex(quelle, 0, nil) else {
    FileHandle.standardError.write("ressourcen/Stifte.png fehlt oder ist kein Bild\n".data(using: .utf8)!)
    exit(1)
}
let seite = 1024
let ctx = CGContext(data: nil, width: seite, height: seite, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 0x1E / 255.0, green: 0x3A / 255.0, blue: 0x5F / 255.0, alpha: 1))   // #1E3A5F
ctx.fill(CGRect(x: 0, y: 0, width: seite, height: seite))
ctx.interpolationQuality = .high
let h = CGFloat(seite) * 0.70
let w = h * CGFloat(stifte.width) / CGFloat(stifte.height)
ctx.draw(stifte, in: CGRect(x: (CGFloat(seite) - w) / 2, y: (CGFloat(seite) - h) / 2, width: w, height: h))
let ziel = CGImageDestinationCreateWithURL(URL(fileURLWithPath: gross) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(ziel, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(ziel) else { exit(1) }
