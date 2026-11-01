import AppKit
import CryptoKit

struct Item: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image, files }

    var id = UUID()
    var kind: Kind
    /// The text itself, or file paths joined by newlines. Empty for images.
    var text: String
    var hasRTF = false
    var imageSize: CGSize?
    var hash: String
    var date = Date()
    var pinned = false
    var sourceApp: String?

    var title: String {
        switch kind {
        case .text:
            let line = text.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) } ?? ""
            return line.trimmingCharacters(in: .whitespaces)
        case .image:
            guard let size = imageSize else { return "Image" }
            return "Image \(Int(size.width)) × \(Int(size.height))"
        case .files:
            let paths = text.split(separator: "\n")
            return paths.count == 1 ? URL(fileURLWithPath: String(paths[0])).lastPathComponent : "\(paths.count) files"
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// History on disk: `items.json` plus `<id>.png` / `<id>.rtf` payload files.
final class Store: ObservableObject {
    @Published private(set) var items: [Item] = []  // newest first

    let dir: URL
    var maxItems = 500
    var maxAge: TimeInterval = 30 * 24 * 3600
    var maxImageBytes = 300_000_000

    private var indexURL: URL { dir.appendingPathComponent("items.json") }

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
        prune()
    }

    func payloadURL(_ item: Item, _ ext: String) -> URL {
        dir.appendingPathComponent("\(item.id.uuidString).\(ext)")
    }

    func add(_ item: Item, rtf: Data? = nil, png: Data? = nil) {
        if let existing = items.first(where: { $0.hash == item.hash }) {
            touch(existing)
            return
        }
        // Write payloads before indexing so a crash never leaves an item without its data.
        do {
            if let rtf { try rtf.write(to: payloadURL(item, "rtf")) }
            if let png { try png.write(to: payloadURL(item, "png")) }
        } catch {
            NSLog("Magpie: could not save payload: \(error)")
            return
        }
        items.insert(item, at: 0)
        prune()
        save()
    }

    /// Moves an item to the top, as if it had just been copied.
    func touch(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        var moved = items.remove(at: i)
        moved.date = Date()
        items.insert(moved, at: 0)
        save()
    }

    func togglePin(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ item: Item) {
        items.removeAll { $0.id == item.id }
        removePayloads(item)
        save()
    }

    func clearUnpinned() {
        items.filter { !$0.pinned }.forEach(removePayloads)
        items.removeAll { !$0.pinned }
        save()
    }

    /// Drops unpinned items past the count, age, or image-size limits. Pinned items always stay.
    func prune(now: Date = Date()) {
        var kept: [Item] = []
        var count = 0
        var imageBytes = 0
        for item in items {
            if item.pinned { kept.append(item); continue }
            var keep = count < maxItems && now.timeIntervalSince(item.date) < maxAge
            if keep, item.kind == .image {
                let size = (try? payloadURL(item, "png").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                imageBytes += size
                keep = imageBytes <= maxImageBytes
            }
            if keep {
                kept.append(item)
                count += 1
            } else {
                removePayloads(item)
            }
        }
        if kept != items {
            items = kept
            save()
        }
    }

    private func removePayloads(_ item: Item) {
        try? FileManager.default.removeItem(at: payloadURL(item, "png"))
        try? FileManager.default.removeItem(at: payloadURL(item, "rtf"))
    }

    private func save() {
        do {
            try JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Magpie: could not save history: \(error)")
        }
    }
}
