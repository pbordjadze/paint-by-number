import Foundation
import FigureRig

/// Preflight the entire existing bundle before any write or cleanup. A redirected child
/// is an error even if this particular command would not write it.
struct OutputDirectory {
    let url: URL
    private let fm = FileManager.default

    init(_ path: String) throws {
        url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        guard url.path != sourceRoot.path, !url.path.hasPrefix(sourceRoot.path + "/") else {
            throw FigureInputError("out: output must be outside the repository: \(url.path)")
        }
        // Also recognize a repository reached from another checkout or via an alias.
        var ancestor = url
        while ancestor.path != "/" {
            let git = ancestor.appendingPathComponent(".git")
            let worktree = (try? String(contentsOf: git, encoding: .utf8))?.hasPrefix("gitdir:") == true
            if worktree || fm.fileExists(atPath: git.appendingPathComponent("HEAD").path) {
                throw FigureInputError("out: output must be outside the repository: \(url.path)")
            }
            ancestor.deleteLastPathComponent()
        }
        try checkTree(url)
    }

    private func checkTree(_ child: URL) throws {
        // attributesOfItem uses lstat, so dangling symlinks are rejected too.
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fm.attributesOfItem(atPath: child.path) }
        catch CocoaError.fileReadNoSuchFile { return }
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw FigureInputError("out: symlinked child is not allowed: \(child.path)")
        }
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            for entry in try fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) {
                try checkTree(entry)
            }
        }
    }

    func child(_ path: String) throws -> URL {
        let child = url.appendingPathComponent(path).standardizedFileURL
        guard child.path.hasPrefix(url.path + "/") else { throw FigureInputError("out: invalid child \(path)") }
        // Check each component, including a frames directory added since preflight.
        var component = child
        while component.path != url.path {
            if let attributes = try? fm.attributesOfItem(atPath: component.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw FigureInputError("out: symlinked child is not allowed: \(component.path)")
            }
            component.deleteLastPathComponent()
        }
        return child
    }

    /// The prior manifest defines ownership. Extension alone never makes a file ours.
    func removePreviousFrames() throws {
        let manifest = try child("manifest.json")
        guard fm.fileExists(atPath: manifest.path) else { return }
        let prior = try JSONDecoder().decode(FigureManifest.self, from: Data(contentsOf: manifest))
        guard (1...216_000).contains(prior.frameCount) else {
            throw FigureInputError("out.manifest.frameCount: expected 1...216000")
        }
        for index in 0..<prior.frameCount {
            for ext in ["svg", "png"] {
                let file = try child("frames/" + frameName(index) + "." + ext)
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            }
        }
    }
}

func frameName(_ index: Int) -> String {
    String(repeating: "0", count: max(0, 4 - String(index).count)) + String(index)
}
