import SwiftUI

extension View {
    /// 何もない場所をタップしたらキーボードを閉じる。
    ///
    /// まとめのメモは複数行なので Return は改行になり、この画面には保存ボタンもない。
    /// 打ち終わりを示す先がないと、キーボードが出たまま残って、まだ保存されていない
    /// ように見える。キーボード上に「完了」を出す手もあるが、あれは Return キーの無い
    /// 数字キーパッドのための最後の手段で、ここでは浮いた札が 1 枚増えるだけになる。
    ///
    /// タップは内容の側で受けるので、テキスト欄やボタンに当たったぶんはそちらが先に
    /// 取る。閉じるのは、どれにも当たらなかったタップだけ。
    func dismissesKeyboardOnBackgroundTap() -> some View {
        contentShape(.rect)
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
    }
}
