import Foundation

enum Shell {
    struct Result: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String

        var succeeded: Bool { status == 0 }
        var output: String { stdout.isEmpty ? stderr : stdout }
    }

    /// Run a system tool and wait for it. Used for ditto, hdiutil, and
    /// codesign — the same tools make-app.sh uses to build these apps.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
