import Foundation
import Testing
@testable import PaintByNumber

/// "Open in Paint by Numbers": the file handler behind `onOpenURL` (`IncomingFile`) and the
/// create flow it feeds. The inbox is a temporary folder standing in for `Documents/Inbox`.
@MainActor
struct OpenURLTests {
    private let fm = FileManager.default

    private func makeFolders() -> (root: URL, inbox: URL) {
        let root = Fixtures.temporaryDirectory()
        let inbox = root.appending(path: "Inbox", directoryHint: .isDirectory)
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        return (root, inbox)
    }

    private func sampleJPEG() throws -> Data {
        try Data(contentsOf: #require(Bundle.main.url(forResource: "parrots", withExtension: "jpg")))
    }

    private func waitUntil(timeout: Duration = .seconds(120), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for the create model")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func aJPEGInTheInboxIsReadDeletedAndOpensTheCreateFlowUnderItsName() async throws {
        let (root, inbox) = makeFolders()
        defer { try? fm.removeItem(at: root) }
        let jpeg = try sampleJPEG()
        let file = inbox.appending(path: "  Garden Walk .JPG")
        try jpeg.write(to: file)

        let image = await IncomingFile.take(file, inbox: inbox)
        #expect(image.data == jpeg)
        #expect(image.title == "Garden Walk")
        #expect(!fm.fileExists(atPath: file.path), "The inbox copy stays behind")

        let model = CreateModel()
        model.load(imageData: image.data, title: image.title)
        #expect(model.defaultTitle == "Garden Walk")
        #expect(model.resolvedTitle == "Garden Walk")
        try await waitUntil { model.source != nil }
        #expect(model.source?.sampleName == nil)
        model.title = "Birds"
        #expect(model.resolvedTitle == "Birds")
        model.cancelAll()
    }

    @Test func aFileThatIsNotAnImageFailsInTheCreateFlowAndIsStillDeleted() async throws {
        let (root, inbox) = makeFolders()
        defer { try? fm.removeItem(at: root) }
        let file = inbox.appending(path: "notes.txt")
        try Data("not an image".utf8).write(to: file)

        let image = await IncomingFile.take(file, inbox: inbox)
        #expect(!image.data.isEmpty)
        #expect(!fm.fileExists(atPath: file.path))

        let model = CreateModel()
        model.load(imageData: image.data, title: image.title)
        try await waitUntil { model.phase != .loading }
        #expect(model.phase == .failed(CreateModel.CreateError.unreadable.localizedDescription))
        #expect(model.source == nil && model.preview == nil)
    }

    @Test func aFileThatCantBeReadYieldsNoDataWhichTheCreateFlowReportsAsUnreadable() async throws {
        let (root, inbox) = makeFolders()
        defer { try? fm.removeItem(at: root) }
        let image = await IncomingFile.take(inbox.appending(path: "Gone.jpg"), inbox: inbox)
        #expect(image.data.isEmpty)
        #expect(image.title == "Gone")

        let model = CreateModel()
        model.load(imageData: image.data, title: image.title)
        try await waitUntil { model.phase != .loading }
        #expect(model.phase == .failed(CreateModel.CreateError.unreadable.localizedDescription))
    }

    @Test func filesOutsideTheInboxAreReadButNeverDeleted() async throws {
        let (root, inbox) = makeFolders()
        defer { try? fm.removeItem(at: root) }
        let jpeg = try sampleJPEG()
        // Files hands out security-scoped URLs to the user's own documents; a sibling folder
        // whose name starts like the inbox's must not pass for it either.
        let lookalike = root.appending(path: "Inbox 2", directoryHint: .isDirectory)
        try fm.createDirectory(at: lookalike, withIntermediateDirectories: true)
        for folder in [root, lookalike] {
            let file = folder.appending(path: "Holiday.jpg")
            try jpeg.write(to: file)
            let image = await IncomingFile.take(file, inbox: inbox)
            #expect(image.data == jpeg)
            #expect(image.title == "Holiday")
            #expect(fm.fileExists(atPath: file.path), "Deleted a file outside the inbox: \(file.path)")
        }
    }

    @Test func onlyRealPathsInsideTheInboxCountAsTheInbox() throws {
        let (root, inbox) = makeFolders()
        defer { try? fm.removeItem(at: root) }
        #expect(IncomingFile.isInInbox(inbox.appending(path: "a.jpg"), inbox: inbox))
        #expect(IncomingFile.isInInbox(inbox.appending(path: "Sub/a.jpg"), inbox: inbox))
        #expect(!IncomingFile.isInInbox(inbox, inbox: inbox), "The inbox itself is not one of its files")
        #expect(!IncomingFile.isInInbox(root.appending(path: "a.jpg"), inbox: inbox))
        #expect(!IncomingFile.isInInbox(root.appending(path: "Inbox 2/a.jpg"), inbox: inbox))
        #expect(!IncomingFile.isInInbox(inbox.appending(path: "../a.jpg"), inbox: inbox))

        // A link inside the inbox that leads out of it is not an inbox copy.
        let outside = root.appending(path: "Keep.jpg")
        try sampleJPEG().write(to: outside)
        let link = inbox.appending(path: "Link.jpg")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!IncomingFile.isInInbox(link, inbox: inbox))
    }

    @Test func discardDeletesInboxCopiesOnly() async throws {
        let (root, inbox) = makeFolders()
        defer { try? fm.removeItem(at: root) }
        let jpeg = try sampleJPEG()
        let inside = inbox.appending(path: "Second.jpg")
        let outside = root.appending(path: "Third.jpg")
        try jpeg.write(to: inside)
        try jpeg.write(to: outside)

        await IncomingFile.discard(inside, inbox: inbox)
        await IncomingFile.discard(outside, inbox: inbox)
        #expect(!fm.fileExists(atPath: inside.path))
        #expect(fm.fileExists(atPath: outside.path))
    }

    @Test func theTitleIsTheFileNameWithoutItsExtensionTrimmed() {
        #expect(IncomingFile.title(for: URL(filePath: "/x/IMG_0042.JPG")) == "IMG_0042")
        #expect(IncomingFile.title(for: URL(filePath: "/x/Beach day.final.png")) == "Beach day.final")
        #expect(IncomingFile.title(for: URL(filePath: "/x/ Trip \n.heic")) == "Trip")
        #expect(IncomingFile.title(for: URL(filePath: "/x/  .jpg")) == nil)
    }

    @Test func aPhotoWithoutAFileNameIsTitledWithTheDate() {
        let model = CreateModel()
        model.load(imageData: Data(), title: nil)
        #expect(model.defaultTitle == Date.now.formatted(.dateTime.month(.wide).day()))
        model.load(imageData: Data(), title: "Harbor")
        #expect(model.defaultTitle == "Harbor")
        model.cancelAll()
    }

    @Test func theAppsInboxIsDocumentsInbox() {
        #expect(IncomingFile.inbox == URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory))
    }
}
