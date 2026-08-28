import AppKit
import CoreGraphics

// ---- 実測値（Materials/screenshots/iphone/appstore-0X.png から） ----
let CW = 1242, CH = 2688
let MARGIN: CGFloat = 119
let DEV = CGRect(x: 157, y: 700, width: 929, height: 1986)   // 端末モック外形（top-left 原点）
let BEZEL: CGFloat = 14
let INNER = DEV.insetBy(dx: BEZEL, dy: BEZEL)                 // 901 x 1958

struct Theme {
    let top: NSColor, bottom: NSColor, head: NSColor, sub: NSColor
    static let light = Theme(top: hexc("E3F4EF"), bottom: hexc("F2F9F7"), head: hexc("054E42"), sub: hexc("5D8179"))
    static let dark  = Theme(top: hexc("007B69"), bottom: hexc("005E50"), head: .white,
                             sub: NSColor.white.withAlphaComponent(0.82))
}
func hexc(_ s: String) -> NSColor {
    var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v>>16)&255)/255, green: CGFloat((v>>8)&255)/255, blue: CGFloat(v&255)/255, alpha: 1)
}

struct Shot {
    let out: String, source: String
    let lines: [String], sub: String
    let dark: Bool, pill: String?
}

// 見出しは 2 行固定。1 行目の帯の上端が headTop に来るように置く。
let HEAD_SIZE: CGFloat = 96
let LINE_GAP: CGFloat = 118
let SUB_SIZE: CGFloat = 46
let PILL_H: CGFloat = 83

func render(_ s: Shot) {
    let theme = s.dark ? Theme.dark : Theme.light
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: CW, pixelsHigh: CH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    // 上下反転して top-left 原点で描く
    g.translateBy(x: 0, y: CGFloat(CH)); g.scaleBy(x: 1, y: -1)

    // 背景グラデーション
    NSGradient(colors: [theme.top, theme.bottom])!
        .draw(in: NSRect(x: 0, y: 0, width: CW, height: CH), angle: -90)

    // 右マージンを割るコピーは、収まるまでフォントを縮める。
    // 1 行に収める版面なので、折り返さずに詰める。
    func fit(_ text: String, _ font: NSFont, max maxW: CGFloat) -> NSFont {
        var f = font
        while (text as NSString).size(withAttributes: [.font: f]).width > maxW, f.pointSize > 24 {
            f = NSFont(name: f.fontName, size: f.pointSize - 1)!
        }
        return f
    }
    func draw(_ text: String, font rawFont: NSFont, color: NSColor, x: CGFloat, top: CGFloat) {
        let font = fit(text, rawFont, max: CGFloat(CW) - MARGIN * 2)
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = NSAttributedString(string: text, attributes: a)
        g.saveGState()
        g.translateBy(x: 0, y: top + font.ascender - font.descender)
        g.scaleBy(x: 1, y: -1)
        line.draw(at: NSPoint(x: x, y: 0))
        g.restoreGState()
    }

    var headTop: CGFloat = 210
    if let pill = s.pill {
        let f = NSFont(name: "HiraginoSans-W7", size: 44)!
        let tw = (pill as NSString).size(withAttributes: [.font: f]).width
        let pw = tw + 40 + 26 + 22 + 34
        let r = NSBezierPath(roundedRect: NSRect(x: MARGIN, y: 170, width: pw, height: PILL_H),
                             xRadius: PILL_H/2, yRadius: PILL_H/2)
        NSColor.white.withAlphaComponent(0.17).setFill(); r.fill()
        NSColor(srgbRed: 0.42, green: 0.87, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: MARGIN + 34, y: 170 + (PILL_H-26)/2, width: 26, height: 26)).fill()
        draw(pill, font: f, color: .white, x: MARGIN + 34 + 26 + 22, top: 170 + (PILL_H - 44*1.18)/2)
        headTop = 315
    }

    let hf = NSFont(name: "HiraginoSans-W8", size: HEAD_SIZE)!
    for (i, l) in s.lines.enumerated() {
        draw(l, font: hf, color: theme.head, x: MARGIN, top: headTop + CGFloat(i) * LINE_GAP)
    }
    let subTop = headTop + CGFloat(s.lines.count) * LINE_GAP + (s.dark ? 37 : 33)
    draw(s.sub, font: NSFont(name: "HiraginoSans-W4", size: SUB_SIZE)!, color: theme.sub, x: MARGIN, top: subTop)

    // 端末モック
    NSColor.black.setFill()
    NSBezierPath(roundedRect: DEV, xRadius: 96, yRadius: 96).fill()
    g.saveGState()
    NSBezierPath(roundedRect: INNER, xRadius: 84, yRadius: 84).addClip()
    // 全体を上下反転した文脈なので、画像は自分の矩形の中でもう一度反転して戻す。
    g.translateBy(x: 0, y: INNER.minY + INNER.maxY)
    g.scaleBy(x: 1, y: -1)
    let src = NSImage(contentsOfFile: s.source)!
    src.draw(in: INNER, from: .zero, operation: .copy, fraction: 1.0)
    g.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: s.out))
    print("  \(s.out)")
}

let V2 = "Materials/screenshots/iphone/v2/"
let RAW = "Materials/screenshots/iphone/"
let OUT = "Materials/screenshots/iphone/v2/final/"
try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)

let shots: [Shot] = [
    Shot(out: OUT+"appstore-01.png", source: V2+"01-comparison.png",
         lines: ["いつもと、", "どれだけ違ったか。"],
         sub: "期間ごとの平均を、いつもの状態と並べます",
         dark: true, pill: "ブリストルログ"),
    Shot(out: OUT+"appstore-02.png", source: V2+"05-today-mixed.png",
         lines: ["やった日も、", "やらなかった日も。"],
         sub: "実施した日としなかった日を分けて集計します",
         dark: false, pill: nil),
    Shot(out: OUT+"appstore-03.png", source: RAW+"02-record.png",
         lines: ["1〜7を選ぶだけで", "1件の記録が残る。"],
         sub: "ブリストル便形状スケール・時刻・腹痛・急な便意",
         dark: false, pill: nil),
    Shot(out: OUT+"appstore-04.png", source: V2+"03-trend-count.png",
         lines: ["期間の区切りが、", "そのままグラフに出る。"],
         sub: "背景の色分けはフェーズ、破線はその期間の平均",
         dark: false, pill: nil),
    Shot(out: OUT+"appstore-05.png", source: V2+"04-trend-bristol.png",
         lines: ["回数・便の形・腹痛・", "便意を同じ軸で追う。"],
         sub: "4つの指標をタブで切り替えて推移を確認",
         dark: false, pill: nil),
    Shot(out: OUT+"appstore-06.png", source: RAW+"05-calendar.png",
         lines: ["1か月の記録と期間を", "カレンダーで一覧。"],
         sub: "日ごとの回数と、フェーズの色をひと目で",
         dark: false, pill: nil),
    Shot(out: OUT+"appstore-07.png", source: RAW+"06-export.png",
         lines: ["PDFとCSVで", "そのまま持っていける。"],
         sub: "診察前の共有にも、手元の控えにも",
         dark: false, pill: nil),
]
for s in shots { render(s) }
print("done")
