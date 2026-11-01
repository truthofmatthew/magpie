import AppKit
import XCTest
@testable import Clipboard

final class StoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func text(_ s: String) -> Item {
        Item(kind: .text, text: s, hash: "t:" + s)
    }

    func testCopyingSameThingAgainMovesItToTop() {
        let store = Store(dir: dir)
        store.add(text("a"))
        store.add(text("b"))
        store.add(text("a"))
        XCTAssertEqual(store.items.map(\.text), ["a", "b"])
    }

    func testPruneKeepsPinnedAndNewestAndDeletesFiles() {
        let store = Store(dir: dir)
        store.maxItems = 2
        store.add(text("pinned"))
        store.togglePin(store.items[0])
        let image = Item(kind: .image, text: "", hash: "img")
        store.add(image, png: Data([1, 2, 3]))
        store.add(text("b"))
        store.add(text("c"))

        XCTAssertEqual(Set(store.items.map(\.hash)), ["t:pinned", "t:b", "t:c"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.payloadURL(image, "png").path))
    }

    func testPruneDropsOldItems() {
        let store = Store(dir: dir)
        store.add(text("old"))
        store.prune(now: Date().addingTimeInterval(31 * 24 * 3600))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testHistorySurvivesRestart() {
        let store = Store(dir: dir)
        store.add(text("kept"))
        store.togglePin(store.items[0])
        let reloaded = Store(dir: dir)
        XCTAssertEqual(reloaded.items, store.items)
    }

    func testCaptureSkipsPasswordManagerCopies() {
        let pb = NSPasteboard(name: .init(UUID().uuidString))
        pb.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("hunter2", forType: .string)
        XCTAssertNil(Pasteboard.capture(pb, sourceApp: nil))
    }

    func testCaptureTextAndImage() throws {
        let pb = NSPasteboard(name: .init(UUID().uuidString))
        pb.clearContents()
        pb.setString("hello", forType: .string)
        XCTAssertEqual(Pasteboard.capture(pb, sourceApp: "Notes")?.item.text, "hello")

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        pb.clearContents()
        pb.setData(rep.representation(using: .png, properties: [:]), forType: .png)
        let capture = try XCTUnwrap(Pasteboard.capture(pb, sourceApp: nil))
        XCTAssertEqual(capture.item.kind, .image)
        XCTAssertEqual(capture.item.imageSize, CGSize(width: 4, height: 3))
    }
}
