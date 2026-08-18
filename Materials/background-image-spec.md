# 背景画像の仕様

外部の画像生成ツールで背景画像を作るときの発注仕様。

---

## 0. 先に一番重要な制約

`project.pbxproj` は `TARGETED_DEVICE_FAMILY = "1,2"`、生成された `Info.plist` の
`UISupportedInterfaceOrientations` は iPhone / iPad とも **縦横どちらも許可** されている。
つまり同じ画像が 9:19.5（iPhone 縦）から 4:3 横（iPad 横）まで引き伸ばされる。

**縦長の絵を作ると破綻する。**

→ **正方形で作り、`scaledToFill` で切らせる** のが唯一の安全策。

| 表示 | 実効ピクセル | 正方形ソースから切られる量 |
|---|---|---|
| iPhone 17 Pro Max 縦 | 1320 × 2868 | 左右が各 **23%** |
| iPad Pro 13" 横 | 2752 × 2064 | 上下が各 **25%** |

したがって **モチーフを持たない一様なにじみ／グラデーション** にすること。
ノート・グラフ・腸・薬などの具体物は入れない（切れるうえ、
「医学的な判断をしない」という本アプリの方針とも合わない）。

---

## 1. 何種類つくるか

| | 使う場所 | 雰囲気 | 要否 |
|---|---|---|---|
| **A** | `OnboardingView` + `PlanSetupView` | 白に溶けかけたミント→スカイの縦グラデ。上が淡いミント、中央はほぼ白、下が淡いスカイ。すりガラス越しの朝の光 | **本命** |
| **B** | `ContentUnavailableView` 4 箇所（今日 / 経過 / プラン / 対象） | A より一段だけ濃く、中心が明るい放射状。記録が貯まれば消える背景 | 任意 |
| — | 今日・経過・カレンダー・設定 | 当初は「敷かない」としていたが、実際に試すと白カードが浮いて見えて良かったため撤回した。7 節を参照 | — |

light / dark がそれぞれ要る。

- **A だけ → 2 ファイル**
- **A + B → 4 ファイル**

dark は「A を暗くしたもの」ではなく **彩度を上げずに沈める**。
深いティール〜ネイビーで、発光させない。

### 空状態の場所（B を作る場合）

- `Feature/Today/TodayView.swift:207`
- `Feature/Trend/TrendView.swift:25`
- `Feature/Settings/PlanListView.swift:13`
- `Feature/Settings/TargetListView.swift:12`

---

## 2. ファイル仕様

| 項目 | 値 |
|---|---|
| 形式 | PNG（アルファなし） |
| カラースペース | sRGB 8bit（Display P3 で出せるならその方が階調は良い） |
| サイズ | **3072 × 3072 正方形**（最低 2048 × 2048） |
| ファイルサイズ | 1 枚 1.5MB 以下を目安 |
| Xcode 側 | Image Set 1 つ、Scales = **Single Scale**（@2x / @3x 不要）、Appearances = **Any + Dark** |
| 名前 | `OnboardingBackground` |

**3072px の根拠**: 一番大きい実効ピクセルが iPhone 17 Pro Max 縦の 1320×2868px と
iPad Pro 13" 横の 2752×2064px。正方形を短辺に合わせて覆うと 2868px 必要になる。
3072 なら拡大なしで全端末をカバーできる。

### 生成ツールからの持ち込み手順

ChatGPT の画像生成は 1024×1024 / 1024×1536 / 1536×1024 しか出せない。

```bash
# 1024 正方形で生成 → 3072 に拡大
sips -Z 3072 input.png --out OnboardingBackground.png
```

ぼかし主体なら拡大の粗さは出ない。
ただし **グレインは拡大後に足す**（先に入れると拡大で潰れる）。

---

## 3. 生成プロンプト

### A / light

```
Extremely subtle abstract gradient wash, square 1:1.
Soft mint-teal (#2EC9B0) at top fading through near-white center
to pale sky-cyan (#16A7C4) at bottom. Desaturated to about 12%
opacity over white — almost white overall. Watercolor bleed,
no shapes, no objects, no text, no vignette, no hard edges.
Uniform enough that any crop looks the same. Fine film grain.
```

### A / dark

```
Same composition, deep navy-teal. Near-black (#0B1416) with a
faint teal glow. Muted, not glowing, no neon.
```

`almost white` と `no shapes` は必ず入れる。生成 AI は放っておくと主役を描く。

### 色の出どころ

アプリアイコン（`Assets.xcassets/AppIcon.appiconset/AppIcon.png`）の縦グラデーションから採取:

| 位置 | 実測値 |
|---|---|
| 上端 | `#2EC9B0`（ミントグリーン） |
| 下端 | `#16A7C4`（シアンブルー） |

---

## 4. 決めておくべきこと

### 4.1 アクセントカラーが未設定

`Assets.xcassets/AccentColor.colorset/Contents.json` に色が入っておらず、
ボタンはシステム青のまま。一方アイコンは teal。
背景を teal に寄せると青ボタンと微妙にズレる。

どちらかを先に決める:

- (a) 背景も AccentColor も teal に統一する
- (b) 背景を無彩色寄りにして、ボタンは青のままにする

### 4.2 コントラスト

背景の上に乗るもの: 黒 / 白のテキスト、`.secondary` のグレー、
`.borderedProminent` のボタン。

- light: 明度 **L\* 92 以上**（ほぼ白）
- dark: 明度 **L\* 15 以下**

これを守れば 4.5:1 を割らない。

### 4.3 バンディング

8bit の緩いグラデーションは iPhone の有機 EL で縞が見える。
**1〜2% のノイズを必ず乗せる。**

---

## 5. 組み込み方

```swift
.background {
    Image(.onboardingBackground)
        .resizable()
        .scaledToFill()
        .ignoresSafeArea()
}
```

### ファイルの置き場

既存のアイコンと同じ運用にする。

- 元データ（生成物そのまま）→ `Materials/images/`
- 採用分 → `TameshiteLog/Assets.xcassets/`

---

## 6. 代替案

この「薄いにじみ」程度の表現なら、iOS 26 の `MeshGradient` を使えば
コード数行・0 バイトで出せる。ダークモード対応もクロップ問題も自動で解決する。

画像で行くなら本書の仕様どおりで問題ないが、選択肢として記録しておく。

---

## 7. 実際に採用したもの（2026-08-18）

Gemini で生成し、`light.jpg` / `dark.jpg` として切り出したものを採用した。

| 項目 | 仕様 | 実際 | 理由 |
|---|---|---|---|
| サイズ | 3072 × 3072 | **998 × 998** | 絵柄が一様なにじみで細部がないため、GPU 側の拡大で見た目が変わらない。3072 PNG は 1 枚 6.8MB、グレインがあるので JPEG / HEIC の高品質でも 3〜6MB になり、背景 1 枚に払う代償として大きすぎる |
| 形式 | PNG | **JPEG** | 生成物がそのまま JPEG。PNG に変換しても情報は増えず、サイズだけ増える |
| ファイルサイズ | 1.5MB 以下 | 各 0.6MB | — |

拡大をアプリ側に任せる代わり、`.interpolation(.high)` を明示している。

輝度の実測値（0〜255）:

| | min | max | mean |
|---|---|---|---|
| light | 203 | 252 | 234 |
| dark | 16 | 81 | 32 |

light は黒文字に対して約 17:1、dark は白文字に対して約 8:1。4.5:1 は十分に満たす。

グレインは生成時点で乗っており、バンディングは出ていない。

### 適用範囲

共通化は `Support/AppBackground.swift` の `View.appBackground()`。

| 画面 | 元の背景 |
|---|---|
| `OnboardingView` | 指定なし（白） |
| `PlanSetupView` | `Color(.systemGroupedBackground)` |
| `TodayView` | `Color(.systemGroupedBackground)` |
| `TrendView` | `Color(.systemGroupedBackground)` |
| `MonthCalendarView` | `Color(.systemGroupedBackground)` |
| `SettingsView` | `List` の既定 |
| `PlanListView` / `TargetListView` / `RecordItemsView` / `NotificationSettingsView` / `DataManagementView` / `AboutView` | `List` / `Form` の既定 |

`List` / `Form` の画面は `.scrollContentBackground(.hidden)` を併せて指定している。
これがないと既定の背景が上に乗って画像が見えない。

シート（`BowelMovementEditor`、`PhaseStartSheet`、`DayDetailView`、各エディタ）は
従来のグレーのまま。iOS ではモーダルが別の面として立っているのが自然なため、
あえて揃えていない。

### 残っている課題

- **`PhasePalette.accents` の先頭が `.teal`**（`Support/PhasePalette.swift`）。背景も teal
  なので、最初の介入フェーズの色がカレンダーの塗りと経過グラフの帯で背景に埋もれる。
  現状フェーズは baseline（グレー）だけなので実害は出ていない。
- 経過タブのセグメンテッドピッカーの未選択トラックが、背景の上でやや濁る。
- 空状態用（B）は未着手。
