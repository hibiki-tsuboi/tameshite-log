import AppKit
import CoreGraphics

let canvasWidth = 1242
let canvasHeight = 2688
let margin: CGFloat = 119
let deviceFrame = CGRect(x: 157, y: 700, width: 929, height: 1986)
let bezel: CGFloat = 14
let screenFrame = deviceFrame.insetBy(dx: bezel, dy: bezel)

struct Theme {
    let top: NSColor
    let bottom: NSColor
    let headline: NSColor
    let subheadline: NSColor

    static let light = Theme(
        top: color("E3F4EF"),
        bottom: color("F2F9F7"),
        headline: color("054E42"),
        subheadline: color("5D8179")
    )
    static let dark = Theme(
        top: color("007B69"),
        bottom: color("005E50"),
        headline: .white,
        subheadline: NSColor.white.withAlphaComponent(0.82)
    )
}

func color(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255,
        alpha: 1
    )
}

struct Shot {
    let output: String
    let source: String
    let lines: [String]
    let subheadline: String
    let usesDarkTheme: Bool
    let pill: String?
}

let headlineSize: CGFloat = 96
let lineGap: CGFloat = 118
let subheadlineSize: CGFloat = 46
let pillHeight: CGFloat = 83

func render(_ shot: Shot) {
    let theme = shot.usesDarkTheme ? Theme.dark : Theme.light
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasWidth,
        pixelsHigh: canvasHeight,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: representation) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let graphics = context.cgContext
    graphics.translateBy(x: 0, y: CGFloat(canvasHeight))
    graphics.scaleBy(x: 1, y: -1)

    NSGradient(colors: [theme.top, theme.bottom])?.draw(
        in: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight),
        angle: -90
    )

    func fittedFont(_ text: String, font: NSFont, maximumWidth: CGFloat) -> NSFont {
        var result = font
        while (text as NSString).size(withAttributes: [.font: result]).width > maximumWidth,
              result.pointSize > 24 {
            result = NSFont(name: result.fontName, size: result.pointSize - 1) ?? result
        }
        return result
    }

    func draw(_ text: String, font originalFont: NSFont, color: NSColor, x: CGFloat, top: CGFloat) {
        let font = fittedFont(text, font: originalFont, maximumWidth: CGFloat(canvasWidth) - margin * 2)
        let line = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
        graphics.saveGState()
        graphics.translateBy(x: 0, y: top + font.ascender - font.descender)
        graphics.scaleBy(x: 1, y: -1)
        line.draw(at: NSPoint(x: x, y: 0))
        graphics.restoreGState()
    }

    var headlineTop: CGFloat = 210
    if let pill = shot.pill {
        let font = NSFont(name: "HiraginoSans-W7", size: 44)!
        let textWidth = (pill as NSString).size(withAttributes: [.font: font]).width
        let pillWidth = textWidth + 40 + 26 + 22 + 34
        let shape = NSBezierPath(
            roundedRect: NSRect(x: margin, y: 170, width: pillWidth, height: pillHeight),
            xRadius: pillHeight / 2,
            yRadius: pillHeight / 2
        )
        NSColor.white.withAlphaComponent(0.17).setFill()
        shape.fill()
        color("6BDEC2").setFill()
        NSBezierPath(
            ovalIn: NSRect(x: margin + 34, y: 170 + (pillHeight - 26) / 2, width: 26, height: 26)
        ).fill()
        draw(
            pill,
            font: font,
            color: .white,
            x: margin + 34 + 26 + 22,
            top: 170 + (pillHeight - 44 * 1.18) / 2
        )
        headlineTop = 315
    }

    let headlineFont = NSFont(name: "HiraginoSans-W8", size: headlineSize)!
    for (index, line) in shot.lines.enumerated() {
        draw(
            line,
            font: headlineFont,
            color: theme.headline,
            x: margin,
            top: headlineTop + CGFloat(index) * lineGap
        )
    }
    let subheadlineTop = headlineTop + CGFloat(shot.lines.count) * lineGap + (shot.usesDarkTheme ? 37 : 33)
    draw(
        shot.subheadline,
        font: NSFont(name: "HiraginoSans-W4", size: subheadlineSize)!,
        color: theme.subheadline,
        x: margin,
        top: subheadlineTop
    )

    NSColor.black.setFill()
    NSBezierPath(roundedRect: deviceFrame, xRadius: 96, yRadius: 96).fill()
    graphics.saveGState()
    NSBezierPath(roundedRect: screenFrame, xRadius: 84, yRadius: 84).addClip()
    graphics.translateBy(x: 0, y: screenFrame.minY + screenFrame.maxY)
    graphics.scaleBy(x: 1, y: -1)
    NSImage(contentsOfFile: shot.source)?.draw(
        in: screenFrame,
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    graphics.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    let data = representation.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: shot.output))
    print(shot.output)
}

let root = "Materials/screenshots/iphone/v3/"
let raw = root + "raw/"
let output = root + "final/"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let shots = [
    Shot(
        output: output + "appstore-01.png",
        source: raw + "01-reproducibility.png",
        lines: ["同じ条件を、", "もう一度。"],
        subheadline: "再現性チェックで、各回の変化方向を見くらべます",
        usesDarkTheme: true,
        pill: "ブリストルログ"
    ),
    Shot(
        output: output + "appstore-02.png",
        source: raw + "02-phase-comparison.png",
        lines: ["期間を区切るから、", "差が見える。"],
        subheadline: "いつもの状態と、試している期間の平均を並べます",
        usesDarkTheme: false,
        pill: nil
    ),
    Shot(
        output: output + "appstore-03.png",
        source: raw + "03-adherence-comparison.png",
        lines: ["やった日と、", "やらなかった日を比較。"],
        subheadline: "未記録を混ぜず、実施の有無で分けて集計します",
        usesDarkTheme: false,
        pill: nil
    ),
    Shot(
        output: output + "appstore-04.png",
        source: raw + "04-record.png",
        lines: ["1〜7を選んで、", "からだの反応も記録。"],
        subheadline: "便の形・時刻・腹痛・急な便意をひとつの画面で",
        usesDarkTheme: false,
        pill: nil
    ),
    Shot(
        output: output + "appstore-05.png",
        source: raw + "05-today.png",
        lines: ["いま試していることを、", "迷わず記録できる。"],
        subheadline: "フェーズと観察対象を、今日の画面にひとまとめ",
        usesDarkTheme: false,
        pill: nil
    ),
    Shot(
        output: output + "appstore-06.png",
        source: raw + "06-history.png",
        lines: ["記録と期間を、", "同じカレンダーで。"],
        subheadline: "日ごとの回数とフェーズの切り替わりを一覧",
        usesDarkTheme: false,
        pill: nil
    ),
    Shot(
        output: output + "appstore-07.png",
        source: raw + "07-export.png",
        lines: ["PDFとCSVで", "そのまま持ち出せる。"],
        subheadline: "診察前の共有にも、手元の控えにも",
        usesDarkTheme: false,
        pill: nil
    ),
]

for shot in shots { render(shot) }
