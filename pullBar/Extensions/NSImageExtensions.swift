//
//  NSImageExtensions.swift
//  pullBar
//
//  Created by Pavel Makhov on 2021-11-21.
//

import Foundation
import SwiftUI

extension NSImage {

    convenience init?(named: String, color: NSColor) {

        let img = NSImage.init(named: named)!
        let newImg = img.tint(color: color)
        self.init(data: newImg.tiffRepresentation!)
    }
    
    static func loadImageAsync(fromURL url: URL, completion: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil,
                  let image = NSImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    func tint(color: NSColor) -> NSImage {
        let newImage = NSImage(size: self.size)
        newImage.lockFocus()

        // Draw with specified transparency
        let imageRect = NSRect(origin: .zero, size: self.size)
        self.draw(in: imageRect, from: imageRect, operation: .sourceOver, fraction: color.alphaComponent)

        // Tint with color
        color.withAlphaComponent(1).set()
        imageRect.fill(using: .sourceAtop)

        newImage.unlockFocus()
        return newImage
    }

    /// Like `tint(color:)`, but resolves `color` each time it is drawn, so semantic colours follow light and dark mode.
    func appearanceTint(color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let resolved = color.usingColorSpace(.sRGB) ?? color
            self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: resolved.alphaComponent)
            resolved.withAlphaComponent(1).set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// A rounded pill holding `text` and an optional SF Symbol, tinted with `color`. It redraws for the
    /// appearance it is drawn in, so it follows light and dark mode.
    static func pill(text: String, symbol: String? = nil, color: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        let symbolSize = symbol
            .flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration) }?
            .size
        let symbolWidth = symbolSize.map { $0.width + 3 } ?? 0
        let height = ceil(textSize.height) + 3
        let size = NSSize(width: ceil(textSize.width + symbolWidth) + 12, height: height)

        return NSImage(size: size, flipped: false) { rect in
            let foreground = color.readable(onDark: NSAppearance.currentDrawing().isDark)
            let radius = (height - 1) / 2
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            foreground.withAlphaComponent(0.16).setFill()
            outline.fill()
            foreground.withAlphaComponent(0.4).setStroke()
            outline.stroke()

            var x: CGFloat = 6
            if let symbol, let symbolSize,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfiguration.applying(.init(paletteColors: [foreground]))) {
                image.draw(in: NSRect(x: x, y: ((height - symbolSize.height) / 2).rounded(), width: symbolSize.width, height: symbolSize.height))
                x += symbolWidth
            }
            (text as NSString).draw(
                at: NSPoint(x: x, y: (height - textSize.height) / 2),
                withAttributes: [.font: font, .foregroundColor: foreground]
            )
            return true
        }
    }
}
