# 背景画像の仕様

外部の画像生成ツールで背景画像を作るときの発注仕様。

---

## 0. 先に一番重要な制約

`project.pbxproj` は `TARGETED_DEVICE_FAMILY = "1,2"`。生成された `Info.plist` の
`UISupportedInterfaceOrientations` は、iPhone は縦のみ、**iPad は縦横どちらも許可**
されている。iPad は Split View や Stage Manager で好きな比率に置かれるので、向きを
固定しても意味がない。つまり同じ画像が 9:19.5（iPhone 縦）から 4:3 横（iPad 横）まで
引き伸ばされる。

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

> **この節は当時の記録。画像は一度撤回し（8 節）、また戻した（9 節）。現状は 9 節を見ること。**

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

---

## 8. 撤回（2026-09-02 に差し替え、2026-09-12 に削除）

`c69619a`「UIをフェーズ比較中心に全面刷新」で `appBackground()` の中身が画像から
コードのグラデーションに変わり、`Image(.appBackground)` の参照はアプリから消えた。
imageset だけが `Assets.xcassets` に残り、描かれないままビルドに入り続けていたので、
2026-09-12 に削除した。原本は 5 節の運用どおり `Materials/images/light.jpg` /
`dark.jpg` に残してある。

いまの背景は `Color(.systemBackground)` の上に、LinearGradient（accentColor 13% →
`ObservationTheme.sand` 12% → clear）と RadialGradient（`ObservationTheme.mint` 12%）
を重ねたもの。6 節で「選択肢として記録しておく」と書いたコード生成側に寄った形になる。

### 画像と比べてどうだったか

カード間のすき間を実測（0〜255）:

| | 画像（7 節） | 現行グラデーション |
|---|---|---|
| light | mean 234 | **248**（243〜252） |
| dark | mean 32 | **30**（25〜33） |

dark は画像とほぼ同じ暗さになる。重ねている 3 色はライト／ダークで切り替わらない固定色
だが、12% でしか乗らず、暗さを決めているのは `Color(.systemBackground)` の側だから。
コントラストは落ちていない。

light は逆に薄くなった。水彩のにじみとグレインは消え、ほぼ純白になっている。1 節の
「白カードが浮いて見えて良かったため撤回した」という採用理由は、いまは効いていない。
取り戻したくなったら、画像を戻すのではなく LinearGradient の opacity を上げること。
同じ見えかたに 1.27MB を払う必要はない。

### 消した理由

- 描かれないまま `Assets.car` に入っていた。light 638,951B + dark 627,946B = **1.27MB**、
  カタログ全体 2,590,368B の **49%**。依存もネットワークもないアプリで、
  ダウンロードサイズの半分近くが一度も画面に出ない画像だった。
- 原本が `Materials/images/` に残るので、消しても失うものがない。

### 7 節の「残っている課題」のその後

- **`PhasePalette.accents` の teal**: パレットは変えていない（先頭は今も `.teal`）が、
  背景の teal が 12% のオーバーレイになったので、帯が埋もれる状況ではなくなった。
- **セグメンテッドピッカーの濁り**: `c69619a` で指標の切り替えがカプセル型のチップに
  変わり、濁っていたトラックそのものがなくなった。
- **空状態用（B）**: 背景がコードになったので、画像としては不要。

### 4.1「アクセントカラーが未設定」のその後

決着は (a)。`AccentColor.colorset` に teal が入り、`TameshiteLogApp` が根で
`.tint(Color(.accent))` を当てている。背景も teal 寄りなのでズレは出ていない。

値はライト `#0A574A` / ダーク `#2FB79E`。アクセントは前景色なので、
ダークでは暗いままにできず、明るい側へ振る必要がある。塗りに使う
`ObservationTheme.ink`（`#0A574A` 固定）とは役割が逆で、ライトでたまたま
同じ値になっているだけ。詳細は `CLAUDE.md` のアクセントカラーの項。

---

## 9. 画像に戻した（2026-09-12）

8 節で消したあと、画像の背景のほうが良かったという判断で元に戻した。
`AppBackground.imageset`（light.jpg / dark.jpg）と、`appBackground()` の
`Image(.appBackground)` 版（`c69619a` で剥がされたもの）をそのまま復帰させている。
`Assets.car` は 1,341,688 → 2,608,808B に戻る。

8 節は「消した状態がどう見えていたか」の測定として残す。そこに書いた
「にじみが欲しいだけなら LinearGradient の opacity を上げるほうが安い」は、
判断が見た目の好みだったので採らなかった。

### 画面上での実測（iPhone 17 Pro / iOS 26.0）

7 節の輝度はソース画像の値。画面上では正方形の左右が切られるので、上端は
それより濃く出る。背景だけを抜いた実測:

| | 上端 | カード間 |
|---|---|---|
| light | RGB (152, 223, 210) | RGB (231, 247, 249) ・ 輝度 mean 243 |
| dark | RGB (34, 71, 74) | RGB (13, 27, 30) ・ 輝度 mean 24 |

上端は 4.2 節の「light は L\* 92 以上（ほぼ白）」を満たしていないが、そこに乗るのは
ステータスバーと、地を持つ歯車ボタンだけなので実害は出ていない。文字が乗る面
（カードとヒーローパネル）での実測は light 6.3〜7.3:1、dark 5.5〜5.6:1 で、
`e7fde89` で直したアクセントのコントラストは画像に戻しても保たれている。

### 7 節の「残っている課題」の扱い

- **`PhasePalette.accents` の先頭の `.teal`**: 背景が再び teal になったので、8 節に
  書いた「解消」は取り消す。ただし 7 節の但し書きのとおり、index 0 は baseline
  （グレー）が占めることが多く、teal が実際に出る場面はほとんどない。
- **セグメンテッドピッカーの濁り**: `c69619a` でカプセル型のチップに変わり、
  濁っていたトラック自体がなくなったまま。こちらは戻らない。
- **空状態用（B）**: 未着手のまま。
