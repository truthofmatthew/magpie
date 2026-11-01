import SwiftUI

enum PasteMode { case paste, pastePlain, copy }

final class PanelModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    /// Bumped on every show so the view can refocus the search field.
    @Published var showCount = 0

    let store: Store
    var choose: (Item, PasteMode) -> Void = { _, _ in }

    init(store: Store) { self.store = store }

    var visible: [Item] {
        let ordered = store.items.filter(\.pinned) + store.items.filter { !$0.pinned }
        guard !query.isEmpty else { return ordered }
        return ordered.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var selected: Item? {
        let items = visible
        return items.indices.contains(selection) ? items[selection] : nil
    }

    func move(_ delta: Int) {
        selection = max(0, min(visible.count - 1, selection + delta))
    }
}

struct HistoryView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.visible
        VStack(spacing: 0) {
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard history")
            Divider()
            if items.isEmpty {
                Spacer()
                Text(model.query.isEmpty ? "Copy something and it shows up here." : "Nothing matches “\(model.query)”.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                Row(item: item, index: index, selected: index == model.selection, store: store)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.choose(item, .paste) }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(index == model.selection ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityAction { model.choose(item, .paste) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selection) { _, selection in
                        if items.indices.contains(selection) { proxy.scrollTo(items[selection].id) }
                    }
                }
            }
            Divider()
            Text("↩ paste   ⇧↩ as plain text   ⌘↩ copy only   ⌘P pin   ⌘⌫ delete")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 460, height: 500)
        .ignoresSafeArea()  // the hidden title bar otherwise leaves an empty strip on top
        .onAppear { searchFocused = true }
        .onChange(of: model.showCount) { searchFocused = true }
    }
}

private struct Row: View {
    let item: Item
    let index: Int
    let selected: Bool
    let store: Store

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? " " : item.title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.pinned {
                Image(systemName: "pin.fill").foregroundStyle(.secondary).accessibilityLabel("Pinned")
            }
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .image:
            if let image = Thumbnails.image(for: item, store: store) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        case .files:
            Image(nsImage: NSWorkspace.shared.icon(forFile: String(item.text.split(separator: "\n")[0])))
                .resizable().frame(width: 32, height: 32)
        case .text:
            Image(systemName: "text.alignleft").foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let time = item.date.formatted(.relative(presentation: .named))
        return [item.sourceApp, time].compactMap { $0 }.joined(separator: " · ")
    }
}

private enum Thumbnails {
    static let cache = NSCache<NSUUID, NSImage>()

    static func image(for item: Item, store: Store) -> NSImage? {
        if let cached = cache.object(forKey: item.id as NSUUID) { return cached }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: 96] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(store.payloadURL(item, "png") as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = NSImage(cgImage: thumb, size: .zero)
        cache.setObject(image, forKey: item.id as NSUUID)
        return image
    }
}
