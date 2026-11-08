import Foundation

enum RDPLauncher {
    static let binaryName = "sdl-freerdp"

    static func resolveBinary(customPath: String) -> String? {
        let fm = FileManager.default

        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, fm.isExecutableFile(atPath: trimmed) {
            return trimmed
        }

        if let bundled = Bundle.main.url(forAuxiliaryExecutable: binaryName),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }

        let candidates = [
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
            "/opt/local/bin/\(binaryName)"
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    static func buildArguments(pc: PC, username: String, domain: String) -> [String] {
        var args: [String] = []

        let host = pc.host.trimmingCharacters(in: .whitespacesAndNewlines)
        args.append("/v:\(host):\(pc.port)")

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty {
            args.append("/u:\(user)")
        }

        let realm = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !realm.isEmpty {
            args.append("/d:\(realm)")
        }

        // Read the password from stdin instead of putting it in the process list.
        args.append("/from-stdin:force")

        switch pc.certificatePolicy {
        case .tofu: args.append("/cert:tofu")
        case .ignore: args.append("/cert:ignore")
        case .deny: args.append("/cert:deny")
        }

        switch pc.displayMode {
        case .fullScreen:
            args.append("/f")
            if pc.dynamicResolution {
                args.append("+dynamic-resolution")
            }
        case .fitWindow:
            args.append("/w:\(max(pc.width, 640))")
            args.append("/h:\(max(pc.height, 480))")
            if pc.dynamicResolution {
                args.append("+dynamic-resolution")
            }
        case .fixedSize:
            args.append("/w:\(max(pc.width, 640))")
            args.append("/h:\(max(pc.height, 480))")
        }

        switch pc.scaling {
        case 100:
            break
        case 140, 180:
            // FreeRDP's /scale shortcut only accepts these two values.
            args.append("/scale:\(pc.scaling)")
        case 125, 150:
            // The desktop scale factor accepts arbitrary percentages; the
            // device factor only has 100/140/180, so use the nearest.
            args.append("/scale-desktop:\(pc.scaling)")
            args.append("/scale-device:140")
        case 175, 200:
            args.append("/scale-desktop:\(pc.scaling)")
            args.append("/scale-device:180")
        default:
            break
        }

        args.append(pc.clipboard ? "/clipboard" : "-clipboard")
        args.append(pc.audio ? "/sound" : "-sound")

        if pc.multiMonitor {
            args.append("/multimon")
        }

        if pc.adminSession == true {
            // RDS servers without an available CAL accept an administrator
            // session, equivalent to mstsc /admin.
            args.append("/admin")
        }

        if pc.shareFolder, !pc.folderPath.isEmpty {
            args.append("/drive:MacShare,\(pc.folderPath)")
        }

        args.append("/network:lan")
        // The SDL connection dialog is a small black progress window; the
        // manager app reports errors itself using the FreeRDP log.
        args.append("-sdl-connection-dialog")
        args.append(contentsOf: parseExtraArguments(pc.extraArguments))
        return args
    }

    static func savedCertificateURL(for pc: PC) -> URL {
        let host = pc.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/freerdp/server/\(host)_\(pc.port).pem")
    }

    static func parseExtraArguments(_ string: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in string {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    static func version(of binary: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = ["/version"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (text?.isEmpty == false) ? text : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
