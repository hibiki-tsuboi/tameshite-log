import PhotosUI
import SwiftUI
import VisionKit

/// 保存前の写真 1 枚。
///
/// 追加の画面ではまだ `ObservationTarget` が存在しないので、保存の瞬間まで
/// `TargetAttachment` を作らずに画像だけ持つ。名前や種類が保存まで反映されないのと同じ扱いで、
/// 途中で画面を離れたときに写真だけ残る、ということが起きない。
struct TargetPhotoDraft: Identifiable {
    let id = UUID()
    let image: Data
    let thumbnail: Data
    /// すでに保存されている添付。この画面で選んだものは nil。
    let attachment: TargetAttachment?

    init(image: Data, attachment: TargetAttachment? = nil) {
        self.image = image
        self.thumbnail = AttachmentImage.thumbnail(from: image) ?? image
        self.attachment = attachment
    }
}

/// 観察対象に添える写真の欄。処方箋や薬の説明書を、用法を確かめるための控えとして持っておく。
struct TargetPhotoSection: View {
    @Binding var photos: [TargetPhotoDraft]

    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: TargetPhotoDraft?
    @State private var isScanning = false
    @State private var isCapturing = false
    @State private var isChoosing = false

    /// 書類スキャナとカメラは端末になければ出さない。シミュレータはどちらも持たない。
    private var canScan: Bool { VNDocumentCameraViewController.isSupported }
    private var canCapture: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Section {
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photos) { photo in
                            thumbnail(photo)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                // sheet と onChange は Section ではなく行の中身に付ける。
                // Section に付けると届かず、写真を押しても何も開かない。
                .sheet(item: $viewing) { photo in
                    PhotoViewer(image: photo.image) {
                        photos.removeAll { $0.id == photo.id }
                    }
                }
            }

            addControl
                .photosPicker(isPresented: $isChoosing, selection: $picked, matching: .images)
                .fullScreenCover(isPresented: $isScanning) {
                    DocumentScanner { pages in
                        isScanning = false
                        append(pages)
                    }
                    .ignoresSafeArea()
                }
                .fullScreenCover(isPresented: $isCapturing) {
                    CameraPicker { image in
                        isCapturing = false
                        append([image].compactMap { $0 })
                    }
                    .ignoresSafeArea()
                }
                .onChange(of: picked) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await load(items) }
                }
        } header: {
            Text("写真")
        } footer: {
            Text("処方箋や薬の説明書を控えておけます。書き出す記録には含まれないので、共有した相手には渡りません。削除は、写真を開くか長押しすると出てきます。")
        }
    }

    /// 撮る手立てがない端末でメニューを出すと、選択肢が 1 つだけの札になる。
    /// そのときはライブラリを開くだけのボタンにする。
    @ViewBuilder
    private var addControl: some View {
        if canScan || canCapture {
            Menu {
                if canScan {
                    Button("書類をスキャン", systemImage: "doc.viewfinder") { isScanning = true }
                }
                if canCapture {
                    Button("写真を撮る", systemImage: "camera") { isCapturing = true }
                }
                Button("ライブラリから選ぶ", systemImage: "photo.on.rectangle") { isChoosing = true }
            } label: {
                Label("写真を追加", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Button("写真を追加", systemImage: "photo.badge.plus") { isChoosing = true }
        }
    }

    private func thumbnail(_ photo: TargetPhotoDraft) -> some View {
        Button {
            viewing = photo
        } label: {
            thumbnailImage(photo)
                .frame(width: 84, height: 84)
                .clipped()
                .clipShape(.rect(cornerRadius: 10))
                // 処方箋は白い紙なので、縁がないと白いカードに沈んで境目が見えない。
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("写真を開く")
        .contextMenu {
            Button("削除", systemImage: "trash", role: .destructive) {
                photos.removeAll { $0.id == photo.id }
            }
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ photo: TargetPhotoDraft) -> some View {
        if let image = UIImage(data: photo.thumbnail) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color(.secondarySystemFill)
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
    }

    /// 選ばれた写真を読み込んで縮小する。
    /// 縮小はそれなりに重いので、`Task.detached` で本流から外す。
    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            await add(raw)
        }
        picked = []
    }

    /// 撮った画像を並びの末尾に足す。スキャナは複数ページを一度に返す。
    private func append(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let encoded = images.compactMap { $0.jpegData(compressionQuality: 0.95) }
        Task {
            for raw in encoded { await add(raw) }
        }
    }

    private func add(_ raw: Data) async {
        guard let image = await Task.detached(priority: .userInitiated, operation: {
            AttachmentImage.prepared(from: raw)
        }).value else { return }
        photos.append(TargetPhotoDraft(image: image))
    }
}

/// 添付写真の拡大表示。処方箋は細かい字を読むためのものなので、拡大できないと控えの用を成さない。
private struct PhotoViewer: View {
    let image: Data
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private static let maxZoom: CGFloat = 6

    var body: some View {
        NavigationStack {
            Group {
                if let uiImage = UIImage(data: image) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(offset)
                        .gesture(magnification.simultaneously(with: drag))
                        .onTapGesture(count: 2) { toggleZoom() }
                        .animation(.snappy, value: zoom)
                } else {
                    ContentUnavailableView("写真を表示できません", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
                // 削除は下に置く。似た紙が並ぶので、開いて中身を確かめてから消せるほうが安全で、
                // それでいて閉じるボタンと取り違えない距離がいる。
                ToolbarItem(placement: .bottomBar) {
                    Button("削除", systemImage: "trash", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .tint(.red)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.visible, for: .bottomBar)
        }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { zoom = clamped(committedZoom * $0.magnification) }
            .onEnded { _ in
                committedZoom = zoom
                if zoom == 1 { resetOffset() }
            }
    }

    /// 等倍のままだと画面ごと動いて見えるので、拡大しているあいだだけ動かせるようにする。
    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard committedZoom > 1 else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func toggleZoom() {
        if committedZoom > 1 {
            zoom = 1
            committedZoom = 1
            resetOffset()
        } else {
            zoom = 3
            committedZoom = 3
        }
    }

    private func resetOffset() {
        offset = .zero
        committedOffset = .zero
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), Self.maxZoom)
    }
}
