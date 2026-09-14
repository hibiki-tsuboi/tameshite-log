import SwiftUI

/// 紙面ビューを 1 ページずつ PDF に描き込む。
///
/// ページの中身は `ReportPagination` が決めているので、ここは描画と入れ物だけを担当する。
///
/// `ImageRenderer` は SwiftUI のビューを描くのでメインアクターから動かせない。
/// 1 年ぶんの書き出しは日別だけで 10 ページを超えるため、全ページを一息に描くと
/// その間ずっと画面が止まり、「準備しています…」がそう見えないまま固まる。
/// ページの区切りでメインループへ返すために async にしてある。
enum ReportPDFRenderer {

    static func render(_ report: ObservationReport, to url: URL) async throws {
        let pages = ReportPagination.pages(for: report)
        var mediaBox = CGRect(origin: .zero, size: ReportLayout.pageSize)

        let info: [CFString: Any] = [
            kCGPDFContextTitle: "\(report.planName) ・ ブリストルログの記録",
            kCGPDFContextCreator: "ブリストルログ",
        ]

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw ExportError.pdfUnavailable
        }

        for (index, page) in pages.enumerated() {
            // 書き出す期間を変えると `.task(id:)` がこの描画を打ち切る。打ち切りを見ずに
            // 描き続けると、新しい準備が `prepareDirectory` で消したディレクトリへ書き込み、
            // 同じ日なら同じファイル名なので新旧 2 つの描画が 1 つの PDF を取り合う。
            try Task.checkCancellation()

            let renderer = ImageRenderer(
                content: ReportPageView(
                    report: report,
                    page: page,
                    pageNumber: index + 1,
                    pageCount: pages.count
                )
            )
            // 紙面ビュー自身が A4 の frame を持っているが、提案サイズも合わせておかないと
            // 描画結果が用紙より小さくなり、PDF の左下に寄ってしまう。
            renderer.proposedSize = ProposedViewSize(ReportLayout.pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }

            // 1 ページ描くごとに手を離す。ページ単位より細かくは切れない。
            await Task.yield()
        }

        try Task.checkCancellation()
        context.closePDF()
    }
}
