import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 添付写真をしまう前の下ごしらえ。
enum AttachmentImage {
    /// 保存する画像の長辺の上限。処方箋は文字が読めなければ意味がないので、
    /// 画面に映すのに要る分より大きく残す。
    nonisolated static let maxPixelSize = 2000

    /// 一覧に並べるサムネイルの長辺。
    nonisolated static let thumbnailPixelSize = 240

    /// 撮ったままの画像を、縮小した JPEG に直す。
    ///
    /// 元のデータをそのまま持たない理由は 2 つ。1 つは大きさで、12MP の写真は 1 枚 3〜5MB あり、
    /// 外部ストレージに置いても端末のバックアップには乗る。もう 1 つは付帯情報で、写真には
    /// 撮影場所の座標が入っていることがある。ここで作り直すと Exif は引き継がれないので、
    /// 位置情報も一緒に落ちる。家で撮った処方箋から自宅の座標が残る、ということが起きない。
    nonisolated static func prepared(from data: Data) -> Data? {
        jpeg(from: data, maxPixelSize: maxPixelSize, quality: 0.8)
    }

    /// 一覧用の小さい画像。全体を展開せず、縮小したものだけを取り出す。
    nonisolated static func thumbnail(from data: Data) -> Data? {
        jpeg(from: data, maxPixelSize: thumbnailPixelSize, quality: 0.7)
    }

    private nonisolated static func jpeg(from data: Data, maxPixelSize: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // 向きは Exif ではなく画素の側に反映させる。付帯情報を捨てるので、
            // ここで倒しておかないと横倒しの処方箋ができあがる。
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
