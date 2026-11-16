// App-Symbol „DammAPP“: Schullogo (Schule Öjendorfer Damm) mittig auf Weiß.
// Aufruf (aus dem Repo-Ordner): swift scripts/symbol.swift <AppIcon-1024.png>   – Quelle: ressourcen/Schullogo.png
// Logo auf 74 % Höhe: so bleibt das Wappen unter der runden Watch-Maske und den iPhone-Ecken ganz sichtbar.
// iOS-Symbole dürfen nicht durchsichtig sein – daher ohne Alphakanal.
import AppKit
import ImageIO

let gross = CommandLine.arguments[1]
guard let quelle = CGImageSourceCreateWithURL(URL(fileURLWithPath: "ressourcen/Schullogo.png") as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(quelle, 0, nil) else {
    FileHandle.standardError.write("ressourcen/Schullogo.png fehlt oder ist kein Bild\n".data(using: .utf8)!)
    exit(1)
}
let seite = 1024
let ctx = CGContext(data: nil, width: seite, height: seite, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: seite, height: seite))
ctx.interpolationQuality = .high
let h = CGFloat(seite) * 0.74
let w = h * CGFloat(logo.width) / CGFloat(logo.height)
ctx.draw(logo, in: CGRect(x: (CGFloat(seite) - w) / 2, y: (CGFloat(seite) - h) / 2, width: w, height: h))
let ziel = CGImageDestinationCreateWithURL(URL(fileURLWithPath: gross) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(ziel, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(ziel) else { exit(1) }
