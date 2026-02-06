import AppKit

// MARK: - ANSI Escape Sequence Parser
// State machine parser: raw terminal output with ANSI SGR codes -> NSAttributedString

struct ANSIParser {

    static let defaultFont = NSFont(name: "Menlo", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont(name: "Menlo-Bold", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let defaultForeground = NSColor.white
    static let defaultBackground = NSColor.clear

    // -------------------------------------------------------------------------------------
    // ----------------------------------- Standard Colors ---------------------------------
    // -------------------------------------------------------------------------------------

    static let standardColors: [NSColor] = [
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0),
        NSColor(red: 0.8, green: 0.3, blue: 0.8, alpha: 1.0),
        NSColor(red: 0.3, green: 0.8, blue: 0.8, alpha: 1.0),
        NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0),
    ]

    static let brightColors: [NSColor] = [
        NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
        NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0),
        NSColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),
        NSColor(red: 1.0, green: 1.0, blue: 0.3, alpha: 1.0),
        NSColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0),
        NSColor(red: 1.0, green: 0.5, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.5, green: 1.0, blue: 1.0, alpha: 1.0),
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
    ]

    // -------------------------------------------------------------------------------------
    // ----------------------------------- State Machine -----------------------------------
    // -------------------------------------------------------------------------------------

    private enum State {
        case normal
        case escape
        case csi
    }

    struct TextStyle {
        var foreground: NSColor = defaultForeground
        var background: NSColor = defaultBackground
        var bold: Bool = false
        var dim: Bool = false
        var underline: Bool = false
        var reverse: Bool = false

        func attributes() -> [NSAttributedString.Key: Any] {
            let font = bold ? ANSIParser.boldFont : ANSIParser.defaultFont

            var fg = foreground
            var bg = background

            if reverse {
                swap(&fg, &bg)
                if bg == defaultBackground { bg = NSColor.white }
                if fg == defaultForeground { fg = NSColor.black }
            }

            if dim {
                fg = fg.withAlphaComponent(0.6)
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fg,
            ]

            if bg != defaultBackground {
                attrs[.backgroundColor] = bg
            }

            if underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            return attrs
        }

        mutating func reset() {
            foreground = defaultForeground
            background = defaultBackground
            bold = false
            dim = false
            underline = false
            reverse = false
        }
    }

    // -------------------------------------------------------------------------------------
    // -------------------------------------- Parse ----------------------------------------
    // -------------------------------------------------------------------------------------

    static func parse(_ raw: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var style = TextStyle()
        var state = State.normal
        var paramBuffer = ""
        var textBuffer = ""

        func flushText() {
            if !textBuffer.isEmpty {
                result.append(NSAttributedString(string: textBuffer, attributes: style.attributes()))
                textBuffer = ""
            }
        }

        for char in raw {
            switch state {
            case .normal:
                if char == "\u{1B}" {
                    flushText()
                    state = .escape
                } else {
                    textBuffer.append(char)
                }

            case .escape:
                if char == "[" {
                    state = .csi
                    paramBuffer = ""
                } else {

                    // Not a CSI sequence, emit the escape and char as-is

                    textBuffer.append("\u{1B}")
                    textBuffer.append(char)
                    state = .normal
                }

            case .csi:
                if char.isNumber || char == ";" {
                    paramBuffer.append(char)
                } else if char == "m" {

                    // SGR sequence complete

                    applySGR(params: paramBuffer, style: &style)
                    state = .normal
                } else {

                    // Non-SGR CSI sequence (cursor movement, etc.) - discard

                    state = .normal
                }
            }
        }

        flushText()
        return result
    }

    // -------------------------------------------------------------------------------------
    // -------------------------------------- SGR ------------------------------------------
    // -------------------------------------------------------------------------------------

    private static func applySGR(params: String, style: inout TextStyle) {
        if params.isEmpty {
            style.reset()
            return
        }

        let codes = params.split(separator: ";").compactMap { Int($0) }
        var i = 0

        while i < codes.count {
            let code = codes[i]

            switch code {
            case 0:
                style.reset()
            case 1:
                style.bold = true
            case 2:
                style.dim = true
            case 4:
                style.underline = true
            case 7:
                style.reverse = true
            case 22:
                style.bold = false
                style.dim = false
            case 24:
                style.underline = false
            case 27:
                style.reverse = false

            // Standard foreground colors

            case 30...37:
                style.foreground = standardColors[code - 30]
            case 39:
                style.foreground = defaultForeground

            // Standard background colors

            case 40...47:
                style.background = standardColors[code - 40]
            case 49:
                style.background = defaultBackground

            // Bright foreground colors

            case 90...97:
                style.foreground = brightColors[code - 90]

            // Bright background colors

            case 100...107:
                style.background = brightColors[code - 100]

            // Extended color: 256-color or 24-bit

            case 38:
                if i + 1 < codes.count {
                    if codes[i + 1] == 5, i + 2 < codes.count {

                        // 256-color foreground

                        style.foreground = color256(codes[i + 2])
                        i += 2
                    } else if codes[i + 1] == 2, i + 4 < codes.count {

                        // 24-bit RGB foreground

                        let r = CGFloat(codes[i + 2]) / 255.0
                        let g = CGFloat(codes[i + 3]) / 255.0
                        let b = CGFloat(codes[i + 4]) / 255.0
                        style.foreground = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                        i += 4
                    }
                }

            case 48:
                if i + 1 < codes.count {
                    if codes[i + 1] == 5, i + 2 < codes.count {

                        // 256-color background

                        style.background = color256(codes[i + 2])
                        i += 2
                    } else if codes[i + 1] == 2, i + 4 < codes.count {

                        // 24-bit RGB background

                        let r = CGFloat(codes[i + 2]) / 255.0
                        let g = CGFloat(codes[i + 3]) / 255.0
                        let b = CGFloat(codes[i + 4]) / 255.0
                        style.background = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                        i += 4
                    }
                }

            default:
                break
            }

            i += 1
        }
    }

    // -------------------------------------------------------------------------------------
    // ----------------------------------- 256-Color Lookup --------------------------------
    // -------------------------------------------------------------------------------------

    private static func color256(_ index: Int) -> NSColor {
        guard index >= 0 && index <= 255 else { return defaultForeground }

        // 0-7: standard colors

        if index < 8 {
            return standardColors[index]
        }

        // 8-15: bright colors

        if index < 16 {
            return brightColors[index - 8]
        }

        // 16-231: 6x6x6 color cube

        if index < 232 {
            let adjusted = index - 16
            let r = CGFloat(adjusted / 36) / 5.0
            let g = CGFloat((adjusted % 36) / 6) / 5.0
            let b = CGFloat(adjusted % 6) / 5.0
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }

        // 232-255: grayscale ramp

        let gray = CGFloat(index - 232) / 23.0
        return NSColor(red: gray, green: gray, blue: gray, alpha: 1.0)
    }
}
