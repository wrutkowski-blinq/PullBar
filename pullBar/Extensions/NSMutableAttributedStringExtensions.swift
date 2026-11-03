//
//  NSMutableAttributedString.swift
//  FleetBar
//
//  Created by Pavel Makhov on 2021-11-04.
//

import Foundation
import SwiftUI

extension NSMutableAttributedString {

    @discardableResult
    func appendString(string: String, color: NSColor = NSColor.secondaryLabelColor) -> NSMutableAttributedString {
        var attributes = [NSAttributedString.Key: AnyObject]()
        attributes[.foregroundColor] = color
        self.append(NSMutableAttributedString(string: string, attributes: attributes))
        
        return self
    }
    
    
    @discardableResult
    func appendString(string: String, color: NSColor, fontSize: CGFloat = NSFont.systemFontSize) -> NSMutableAttributedString {

        var attributes = [NSAttributedString.Key: AnyObject]()
        attributes[.foregroundColor] = color
        attributes[.font] = NSFont.systemFont(ofSize: fontSize)
        self.append(NSMutableAttributedString(string: string, attributes: attributes))

        return self
    }

    @discardableResult
    func appendString(string: String, color: NSColor, font: NSFont, kern: CGFloat = 0) -> NSMutableAttributedString {
        self.append(NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font, .kern: kern]))
        return self
    }

    /// Appends `text` as a rounded pill tinted with `color`, vertically centred on text set in `lineFont`.
    @discardableResult
    func appendPill(text: String, symbol: String? = nil, color: NSColor, lineFont: NSFont) -> NSMutableAttributedString {
        let image = NSImage.pill(text: text, symbol: symbol, color: color)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: ((lineFont.capHeight - image.size.height) / 2).rounded(),
            width: image.size.width,
            height: image.size.height
        )
        self.append(NSAttributedString(attachment: attachment))
        return self
    }

    @discardableResult
    func appendIcon(iconName: String, color: NSColor = NSColor.secondaryLabelColor) -> NSMutableAttributedString {
        let image = NSImage(named: iconName)?.appearanceTint(color: color, size: NSSize(width: 12, height: 12))
        let image1Attachment = NSTextAttachment()
        image1Attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        image1Attachment.image = image
        let image1String = NSMutableAttributedString(attachment: image1Attachment)
        let range = NSMakeRange(0,image1String.length)
        image1String.addAttribute(NSAttributedString.Key.baselineOffset, value: -1.0, range: range)
        self.append(image1String)
        self.appendString(string: " ")
        
        return self
    }

    @discardableResult
    func appendSeparator() -> NSMutableAttributedString {
        self.append(NSMutableAttributedString(string: "   "))
        return self
    }
    
    @discardableResult
    func appendNewLine() -> NSMutableAttributedString {
        self.append(NSMutableAttributedString(string: "\n"))
        return self
    }
}

func hexColor (hex: String) -> NSColor {
    var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if (cString.hasPrefix("#")) {
        cString.remove(at: cString.startIndex)
    }

    if ((cString.count) != 6) {
        return NSColor.gray
    }

    var rgbValue:UInt64 = 0
    Scanner(string: cString).scanHexInt64(&rgbValue)

    return NSColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    )
}

extension NSColor {

    /// This colour mixed toward white on a dark background, or black on a light one, until it is legible as text.
    func readable(onDark: Bool) -> NSColor {
        guard let base = usingColorSpace(.sRGB) else { return self }
        let target: NSColor = onDark ? .white : .black
        var color = base
        var fraction: CGFloat = 0
        while fraction < 1 && (onDark ? color.relativeLuminance < 0.35 : color.relativeLuminance > 0.15) {
            fraction += 0.1
            color = base.blended(withFraction: fraction, of: target)?.usingColorSpace(.sRGB) ?? base
        }
        return color
    }

    var readable: NSColor {
        NSColor(name: nil) { appearance in
            var color = self
            appearance.performAsCurrentDrawingAppearance {
                color = self.readable(onDark: appearance.isDark)
            }
            return color
        }
    }

    private var relativeLuminance: CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(redComponent) + 0.7152 * linear(greenComponent) + 0.0722 * linear(blueComponent)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
