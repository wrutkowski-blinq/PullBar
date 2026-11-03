//
//  GhCli.swift
//  pullBar
//

import Foundation
import Defaults

/// Supplies the token the `gh` CLI is logged in with, so the app needs no personal access token.
enum GhCli {

    // Apps launched from Finder get PATH=/usr/bin:/bin:/usr/sbin:/sbin, which misses Homebrew.
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    private static var cachedToken: String?

    static var token: String {
        if let cachedToken {
            return cachedToken
        }
        let token = readToken() ?? ""
        if !token.isEmpty {
            cachedToken = token
        }
        return token
    }

    /// Makes the next `token` read ask `gh` again.
    static func invalidate() {
        cachedToken = nil
    }

    static var hostname: String {
        let host = URL(string: Defaults[.githubApiBaseUrl])?.host ?? "github.com"
        return host == "api.github.com" ? "github.com" : host
    }

    private static var executableURL: URL? {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (pathDirs + searchPaths)
            .map { URL(fileURLWithPath: $0).appendingPathComponent("gh") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func readToken() -> String? {
        guard let executableURL else {
            NSLog("gh not found in PATH or %@", searchPaths.joined(separator: ", "))
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["auth", "token", "--hostname", hostname]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            NSLog("Failed to run gh: %@", error.localizedDescription)
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            NSLog("gh auth token exited with %d", process.terminationStatus)
            return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
