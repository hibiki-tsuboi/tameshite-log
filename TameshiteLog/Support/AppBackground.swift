import SwiftUI

extension View {
    /// アプリ全体の背景。
    ///
    /// 画像は正方形。iPhone / iPad の縦横どちらでも表示されるので画面比が
    /// 0.46〜1.33 まで振れる。縦長の絵を敷くと破綻するため、正方形を
    /// scaledToFill で覆い、あふれた分は切らせている。iPhone 縦では左右が
    /// 各 23%、iPad 横では上下が各 25% 切れる前提の絵柄。
    ///
    /// List / Form に敷くときは、既定の背景が上に乗るので
    /// `.scrollContentBackground(.hidden)` を合わせて指定する。
    func appBackground() -> some View {
        background {
            Image(.appBackground)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .ignoresSafeArea()
        }
    }
}
