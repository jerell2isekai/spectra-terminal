import Foundation

/// Parses `git status --porcelain=v1` output to determine file-level git status.
enum GitStatusProvider {

    /// Fetch current branch name. Returns nil if not a git repo.
    static func fetchBranch(for rootURL: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        task.currentDirectoryURL = rootURL

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if the given directory is inside a git repository.
    static func isGitRepo(at rootURL: URL) -> Bool {
        fetchBranch(for: rootURL) != nil
    }

    /// Fetch git status for all files under the given root directory.
    /// Returns a dictionary mapping relative file paths to their git status.
    static func fetchStatus(for rootURL: URL) -> [String: FileNode.GitStatus] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["status", "--porcelain=v1", "-uall"]
        task.currentDirectoryURL = rootURL

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return [:] }

        // Read pipe BEFORE waitUntilExit to avoid deadlock when output exceeds pipe buffer
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var statuses: [String: FileNode.GitStatus] = [:]
        for line in output.split(separator: "\n") {
            guard line.count >= 4 else { continue }
            let statusCode = String(line.prefix(2))
            var filePath = String(line.dropFirst(3))

            // Handle renames: "R  old -> new" — use the destination path
            if filePath.contains(" -> ") {
                filePath = String(filePath.split(separator: " -> ").last ?? Substring(filePath))
            }
            // Unquote paths that git wraps in double quotes
            if filePath.hasPrefix("\"") && filePath.hasSuffix("\"") {
                filePath = String(filePath.dropFirst().dropLast())
            }

            let status: FileNode.GitStatus
            switch statusCode.trimmingCharacters(in: .whitespaces) {
            case "M", "MM", "AM": status = .modified
            case "A":             status = .added
            case "D":             status = .deleted
            case "R":             status = .modified  // renamed
            case "??":            status = .untracked
            case "UU", "AA":      status = .conflicted
            default:              status = .modified
            }
            statuses[filePath] = status
        }
        return statuses
    }

    /// Fetch unified diff for a single file.
    static func fetchFileDiff(filePath: String, repoURL: URL) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["diff", "HEAD", "--", filePath]
        task.currentDirectoryURL = repoURL

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        // If no staged/unstaged diff vs HEAD, try diff for untracked files (show full content)
        if data.isEmpty {
            return fetchUntrackedContent(filePath: filePath, repoURL: repoURL)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func fetchUntrackedContent(filePath: String, repoURL: URL) -> String {
        let fullPath = repoURL.appendingPathComponent(filePath)
        guard let content = try? String(contentsOf: fullPath, encoding: .utf8) else { return "" }
        let lines = content.components(separatedBy: "\n")
        var result = "diff --git a/\(filePath) b/\(filePath)\n"
        result += "new file\n"
        result += "--- /dev/null\n"
        result += "+++ b/\(filePath)\n"
        result += "@@ -0,0 +1,\(lines.count) @@\n"
        for line in lines {
            result += "+\(line)\n"
        }
        return result
    }

    /// Discover git repositories at rootURL and in its immediate subdirectories.
    /// Returns an array of (repoURL, branch, statuses) tuples.
    struct RepoInfo {
        let url: URL
        let branch: String
        let statuses: [String: FileNode.GitStatus]
    }

    static func discoverGitRepos(under rootURL: URL) -> [RepoInfo] {
        var repos: [RepoInfo] = []

        // Check root itself
        if let branch = fetchBranch(for: rootURL) {
            let statuses = fetchStatus(for: rootURL)
            repos.append(RepoInfo(url: rootURL, branch: branch, statuses: statuses))
        }

        // Check immediate subdirectories
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return repos }

        for subdir in contents {
            let isDir = (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            // Skip if this subdir is inside the root's git repo (same .git)
            if !repos.isEmpty && repos[0].url == rootURL {
                // Root is already a git repo; subdirs are part of it, not separate repos
                // Only check subdirs that have their own .git
                let gitDir = subdir.appendingPathComponent(".git")
                guard FileManager.default.fileExists(atPath: gitDir.path) else { continue }
            }
            if let branch = fetchBranch(for: subdir) {
                // Verify it's truly a separate repo (has its own .git)
                let gitDir = subdir.appendingPathComponent(".git")
                guard FileManager.default.fileExists(atPath: gitDir.path) else { continue }
                let statuses = fetchStatus(for: subdir)
                repos.append(RepoInfo(url: subdir, branch: branch, statuses: statuses))
            }
        }

        return repos
    }

    /// Apply git statuses to a file tree recursively.
    /// Directories inherit "modified" if any child is non-clean.
    static func applyStatuses(_ statuses: [String: FileNode.GitStatus],
                              to node: FileNode,
                              rootURL: URL) {
        let rootPath = rootURL.path
        let nodePath = node.url.path
        let relativePath: String
        if nodePath.hasPrefix(rootPath + "/") {
            relativePath = String(nodePath.dropFirst(rootPath.count + 1))
        } else {
            relativePath = node.name
        }

        if let status = statuses[relativePath] {
            node.gitStatus = status
        }

        if let children = node.children {
            for child in children {
                applyStatuses(statuses, to: child, rootURL: rootURL)
            }
            // Propagate: directory is modified if any child is non-clean
            if node.gitStatus == .unmodified,
               children.contains(where: { $0.gitStatus != .unmodified }) {
                node.gitStatus = .modified
            }
        }
    }
}
