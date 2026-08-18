import Foundation
import SwiftData

/// 観察対象に添えておく写真。処方箋や薬剤情報提供書など、用法を確かめるための控え。
///
/// 書き出しには入れない。処方箋には氏名・生年月日・保険者番号・医療機関名が載っていて、
/// PDF と CSV は人に渡すために作るものなので、混ざると渡した相手にそれが全部渡る。しかも
/// 渡した時点では気づけない。`ReportPageView` と `ExportService` はこの型を参照しないこと。
@Model
final class TargetAttachment {
    /// 縮小して JPEG に直した画像。外部ストレージなので、本体のストアは膨らまない。
    @Attribute(.externalStorage) var image: Data = Data()
    var createdAt: Date = Date.distantPast
    var target: ObservationTarget?

    init(image: Data, createdAt: Date = .now, target: ObservationTarget? = nil) {
        self.image = image
        self.createdAt = createdAt
        self.target = target
    }
}
