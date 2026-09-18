import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(macOS) || os(Linux)

internal final class S3CommandRunner: IOActor {

    private static let poolSize = min(max(Flynn.cores / 2, 2), 8)

    private static let pool: [S3CommandRunner] = (0..<poolSize).map { _ in S3CommandRunner() }

    private static let rotationLock = NSLock()
    private static var rotation = 0

    internal static func next() -> S3CommandRunner {
        if let idle = pool.first(where: { $0.unsafeMessagesCount == 0 }) {
            return idle
        }
        rotationLock.lock(); defer { rotationLock.unlock() }
        rotation = (rotation + 1) % pool.count
        return pool[rotation]
    }

    private func confirmConfigFile(maxConcurrent: Int) -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("aws-config")
        let contents = """
        [default]
        s3 =
          max_concurrent_requests = \(maxConcurrent)
        """
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func environment(for credentials: S3Credentials,
                             configFile: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let configFile = configFile {
            env["AWS_CONFIG_FILE"] = configFile
        }
        env["AWS_ACCESS_KEY_ID"] = credentials.accessKey
        env["AWS_SECRET_ACCESS_KEY"] = credentials.secretKey
        env["AWS_DEFAULT_REGION"] = credentials.region
        return env
    }

    private func run(executable: String,
                     arguments: [String],
                     environment: [String: String],
                     onLine: (String) -> ()) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
        } catch {
            return "failed to run aws cli: \(error)"
        }

        // The child holds its own copy of the write end; this side must let go
        // of it or the read below never sees EOF.
        outputPipe.fileHandleForWriting.closeFile()

        let readHandle = outputPipe.fileHandleForReading
        let newline = UInt8(ascii: "\n")
        var pending = Data()

        while true {
            let chunk = readHandle.availableData
            if chunk.isEmpty { break } // EOF

            pending.append(chunk)

            while let index = pending.firstIndex(of: newline) {
                if let line = String(data: pending.subdata(in: pending.startIndex..<index),
                                     encoding: .utf8) {
                    onLine(line)
                }
                pending.removeSubrange(pending.startIndex...index)
            }
        }

        // A final line with no trailing newline, if aws ended that way.
        if pending.isEmpty == false,
           let line = String(data: pending, encoding: .utf8) {
            onLine(line)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return "aws cli failed code \(process.terminationStatus)"
        }
        return nil
    }

    // MARK: - behaviors

    internal func _beUpload(executable: String,
                            credentials: S3Credentials,
                            key: String,
                            filePath: String,
                            _ returnCallback: @escaping (String?) -> Void) {
        let keyPath = (key.hasPrefix("/") ? key : "/" + key).replacingOccurrences(of: " ", with: "+")

        let error = run(executable: executable,
                        arguments: [
                            "s3",
                            "cp",
                            filePath,
                            "s3://\(credentials.bucket)\(keyPath)",
                            "--no-progress"
                        ],
                        environment: environment(for: credentials, configFile: nil),
                        onLine: { _ in })

        returnCallback(error)
    }

    internal func _beSyncToLocal(executable: String,
                                 credentials: S3Credentials,
                                 keyPrefix: String,
                                 localDirectory: String,
                                 continuous: Bool,
                                 _ onProgress: @escaping (Int) -> (),
                                 _ returnCallback: @escaping ([S3Object], [S3Object], String?, String?) -> Void) {
        var arguments: [String] = [
            "s3",
            "sync",
            "s3://\(credentials.bucket)/\(keyPrefix)",
            localDirectory,
            "--no-progress"
        ]

        var allObjects: [S3Object] = []
        var modifiedObjects: [S3Object] = []

        // Walking the local tree is disk IO, so it belongs on this thread too,
        // not on the scheduler thread of whoever asked for the sync.
        let localDirectoryUrl = URL(fileURLWithPath: localDirectory)
        var localFilesByS3Key: [String: LocalFile] = [:]
        var localFilesSorted: [LocalFile] = []
        if let enumerator = FileManager.default.enumerator(at: localDirectoryUrl,
                                                           includingPropertiesForKeys: [.isRegularFileKey],
                                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: Set([.isRegularFileKey])) else { continue }
                guard resourceValues.isRegularFile == true else { continue }

                // Note: this does not handle paths which repeat like /a/b/and/more/a/b/and/file.txt?
                guard let relativePath = fileURL.path.components(separatedBy: localDirectoryUrl.path).last else { continue }
                var s3Key = keyPrefix + relativePath
                s3Key = s3Key.replacingOccurrences(of: "//", with: "/")

                let localFile = LocalFile(name: fileURL.lastPathComponent,
                                          path: fileURL.path,
                                          s3Key: s3Key)

                // to match existing logic in non-AWS version
                if continuous == false || allObjects.count < 999 {
                    allObjects.append(
                        S3Object(keyPrefix: keyPrefix,
                                 key: s3Key,
                                 localFile: fileURL.path)
                    )
                }

                localFilesByS3Key[s3Key] = localFile
                localFilesSorted.append(localFile)
            }
        }

        localFilesSorted.sort()

        // If our sorting of the local files and s3 bucket were perfect, then we could pick up
        // where the last file left off. However, given time drift of user devices it is entirely
        // possible that the sorting will leave gaps. To combat this, we allow up to one extra list
        // API call for continuous pulls.
        if continuous && localFilesSorted.count >= 999 {
            let marker = localFilesSorted[localFilesSorted.count - 999].s3Key
            arguments.append("--start-after")
            arguments.append(marker)
        }

        var parseError: String? = nil
        var reportedCount = 0

        let runError = run(executable: executable,
                           arguments: arguments,
                           environment: environment(for: credentials,
                                                    configFile: confirmConfigFile(maxConcurrent: 64)),
                           onLine: { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { return }

            if let object = S3Object.from(awsLog: line) {
                allObjects.append(object)
                modifiedObjects.append(object)
            } else {
                parseError = "failed to parse aws output: \(line)"
            }

            // Progress is reported per line rather than per read, which is what
            // the previous per-chunk batching amounted to for small outputs.
            let total = allObjects.count
            if total != reportedCount {
                reportedCount = total
                onProgress(total)
            }
        })

        if let runError = runError {
            return returnCallback([], [], nil, runError)
        }

        returnCallback(allObjects, modifiedObjects, nil, parseError)
    }
}

#endif
