import Foundation
import os
import Testing
@testable import PaintByNumber

/// Sending feedback to the developers: the multipart body and the request that carries it, the
/// relay's answers, and which uploader a launch uses (Debug builds, which every test and CI run
/// is, never reach the relay).
struct FeedbackUploaderTests {
    private let report = Data("# Fox: feedback\r\nline two\n".utf8)
    private let picture = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF])
    private let bundle = Data([0x50, 0x4B, 0x03, 0x04, 0x0D, 0x0A])

    private func sampleParts(bundleName: String = "Fox Feedback 2026-10-05 14.32.zip") -> [FeedbackUploader.Part] {
        [
            FeedbackUploader.Part(name: "report", filename: "feedback.md", contentType: "text/markdown; charset=utf-8", data: report),
            FeedbackUploader.Part(
                name: "picture", filename: "Fox Feedback 2026-10-05 14.32.png", contentType: "image/png", data: picture),
            FeedbackUploader.Part(name: "bundle", filename: bundleName, contentType: "application/zip", data: bundle),
        ]
    }

    /// Files on disk as `FeedbackPackage.write` leaves them, in a folder of their own.
    private func writeSampleFiles() throws -> (files: FeedbackPackage.Files, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FeedbackUploaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = FeedbackPackage.Files(
            picture: folder.appending(path: "Fox Feedback 2026-10-05 14.32.png"),
            bundle: folder.appending(path: "Fox Feedback 2026-10-05 14.32.zip"),
            report: folder.appending(path: "feedback.md"))
        try picture.write(to: files.picture)
        try bundle.write(to: files.bundle)
        try report.write(to: files.report)
        return (files, folder)
    }

    // MARK: The body

    @Test func bodyHasEachPartWithItsNameFileAndTypeBetweenBoundaries() {
        var expected = Data()
        func add(_ text: String) { expected.append(Data(text.utf8)) }
        add("--XYZ\r\nContent-Disposition: form-data; name=\"report\"; filename=\"feedback.md\"\r\n")
        add("Content-Type: text/markdown; charset=utf-8\r\n\r\n")
        expected.append(report)
        add("\r\n--XYZ\r\nContent-Disposition: form-data; name=\"picture\"; filename=\"Fox Feedback 2026-10-05 14.32.png\"\r\n")
        add("Content-Type: image/png\r\n\r\n")
        expected.append(picture)
        add("\r\n--XYZ\r\nContent-Disposition: form-data; name=\"bundle\"; filename=\"Fox Feedback 2026-10-05 14.32.zip\"\r\n")
        add("Content-Type: application/zip\r\n\r\n")
        expected.append(bundle)
        add("\r\n--XYZ--\r\n")
        #expect(FeedbackUploader.body(of: sampleParts(), boundary: "XYZ") == expected)
    }

    /// A quote or a line break in a name would end its header early.
    @Test func fileNamesAreQuotedForTheirHeader() {
        let body = FeedbackUploader.body(of: sampleParts(bundleName: "Fox \"Feedback\"\r\n.zip"), boundary: "XYZ")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"bundle\"; filename=\"Fox %22Feedback%22%0D%0A.zip\"\r\n"))
    }

    @Test func eachBoundaryIsNewAndDelimitsEveryPartOnce() {
        let first = FeedbackUploader.makeBoundary(), second = FeedbackUploader.makeBoundary()
        #expect(first != second)
        #expect(first.hasPrefix("moonlight-"))
        let text = String(decoding: FeedbackUploader.body(of: sampleParts(), boundary: first), as: UTF8.self)
        // Three parts open with it and the body closes with it.
        #expect(text.components(separatedBy: "--\(first)").count - 1 == 4)
        #expect(text.hasSuffix("--\(first)--\r\n"))
    }

    @Test func partsAreReadFromTheFilesInTheOrderTheRelayExpects() throws {
        let (files, folder) = try writeSampleFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let parts = try FeedbackUploader.parts(of: files)
        #expect(parts.map(\.name) == ["report", "picture", "bundle"])
        #expect(parts.map(\.contentType) == ["text/markdown; charset=utf-8", "image/png", "application/zip"])
        #expect(parts.map(\.filename) == ["feedback.md", "Fox Feedback 2026-10-05 14.32.png", "Fox Feedback 2026-10-05 14.32.zip"])
        #expect(parts.map(\.data) == [report, picture, bundle])
    }

    // MARK: The request

    @Test func theEndpointIsTheRelaysFeedbackPath() {
        #expect(FeedbackUploader.endpoint.absoluteString == "https://moonlight-feedback.paul-bordjadze.workers.dev/v1/feedback")
    }

    @Test func requestPostsFormDataWithTheAppVersionAndASixtySecondTimeout() {
        let request = FeedbackUploader.request(to: FeedbackUploader.endpoint, app: "1.0.42 (42)", boundary: "XYZ")
        #expect(request.httpMethod == "POST")
        #expect(request.url == FeedbackUploader.endpoint)
        #expect(request.timeoutInterval == 60)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=XYZ")
        #expect(request.value(forHTTPHeaderField: "X-Moonlight-App") == "1.0.42 (42)")
    }

    @Test func onlyA2xxAnswerIsSent() throws {
        let url = FeedbackUploader.endpoint
        func answer(_ status: Int) -> URLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        }
        try FeedbackUploader.check(answer(201))
        try FeedbackUploader.check(answer(200))
        for status in [301, 400, 404, 413, 429, 500, 502] {
            #expect(throws: FeedbackUploader.UploadError.refused(status)) { try FeedbackUploader.check(answer(status)) }
        }
        #expect(throws: FeedbackUploader.UploadError.notHTTP) {
            try FeedbackUploader.check(URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
    }

    /// The live uploader against a session whose requests never leave the process: what it posts,
    /// and what a refusal does.
    @Test func liveUploaderPostsTheFilesAndFailsOnARefusal() async throws {
        let (files, folder) = try writeSampleFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubRelay.self]
        let endpoint = try #require(URL(string: "https://relay.example/v1/feedback"))
        let uploader = FeedbackUploader.live(endpoint: endpoint, session: URLSession(configuration: configuration))
        #expect(uploader.name == "live")

        StubRelay.reset(status: 201)
        try await uploader.upload(files, app: "1.0 (7)")
        let sent = StubRelay.sent()
        #expect(sent.count == 1)
        let post = try #require(sent.first)
        #expect(post.request.httpMethod == "POST")
        #expect(post.request.url == endpoint)
        #expect(post.request.value(forHTTPHeaderField: "X-Moonlight-App") == "1.0 (7)")
        let contentType = try #require(post.request.value(forHTTPHeaderField: "Content-Type"))
        let prefix = "multipart/form-data; boundary="
        #expect(contentType.hasPrefix(prefix))
        let boundary = String(contentType.dropFirst(prefix.count))
        #expect(boundary.hasPrefix("moonlight-"))
        let parts = try FeedbackUploader.parts(of: files)
        #expect(post.body == FeedbackUploader.body(of: parts, boundary: boundary))

        StubRelay.reset(status: 500)
        await #expect(throws: FeedbackUploader.UploadError.refused(500)) {
            try await uploader.upload(files, app: "1.0 (7)")
        }
        StubRelay.reset(status: 429)
        await #expect(throws: FeedbackUploader.UploadError.refused(429)) {
            try await uploader.upload(files, app: "1.0 (7)")
        }
    }

    // MARK: Which uploader

    #if DEBUG
    /// Debug builds are what every test and CI run is: they send nothing unless asked to.
    @Test func debugLaunchesUseAStubUnlessTheArgumentSaysLive() {
        #expect(FeedbackUploadStub.choose(argument: nil).name == "stub")
        #expect(FeedbackUploadStub.choose(argument: "").name == "stub")
        #expect(FeedbackUploadStub.choose(argument: "anything else").name == "stub")
        #expect(FeedbackUploadStub.choose(argument: "fail").name == "stub-failing")
        #expect(FeedbackUploadStub.choose(argument: "fail-once").name == "stub-failing-once")
        #expect(FeedbackUploadStub.choose(argument: "live").name == "live")
    }

    @Test func theTestHostsUploaderIsAStub() {
        #expect(FeedbackUploads.current.name == "stub")
    }

    @Test func theStubSucceedsAndTheFailingStubFails() async throws {
        let (files, folder) = try writeSampleFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await FeedbackUploadStub.choose(argument: nil).upload(files, app: "1.0 (7)")
        await #expect(throws: URLError.self) {
            try await FeedbackUploadStub.choose(argument: "fail").upload(files, app: "1.0 (7)")
        }
    }
    #endif
}

/// A URL protocol that answers every request with a status and keeps what was sent, so an upload
/// can be run without a network. One test uses it at a time.
private final class StubRelay: URLProtocol {
    struct Sent {
        var request: URLRequest
        var body: Data
    }

    private struct State {
        var status = 201
        var sent: [Sent] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func reset(status: Int) {
        state.withLock { current in current = State(status: status) }
    }

    static func sent() -> [Sent] {
        state.withLock { current in current.sent }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        } else if let data = request.httpBody {
            body = data
        }
        let sent = Sent(request: request, body: body)
        let status = Self.state.withLock { current in
            current.sent.append(sent)
            return current.status
        }
        if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
