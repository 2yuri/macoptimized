import Foundation

enum Shell {
    struct Result { let status: Int32; let output: String }

    /// Runs an executable directly (no shell interpolation).
    @discardableResult
    static func run(_ path: String, _ args: [String] = []) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return Result(status: -1, output: error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a command as root via the standard macOS admin password prompt.
    /// Arguments are single-quoted so nothing is shell-expanded.
    @discardableResult
    static func runAsAdmin(_ path: String, _ args: [String] = []) -> Result {
        let quoted = ([path] + args).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let escaped = quoted.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }
}
