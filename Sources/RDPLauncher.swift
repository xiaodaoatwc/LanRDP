import Foundation
import AppKit

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

    /// macOS logical resolution of the main screen, as shown in System Settings
    /// (the fullscreen area; the notch and menu bar are already accounted for by
    /// the display mode, so nothing is subtracted here).
    static func logicalFullscreenSize() -> (width: Int, height: Int)? {
        guard let screen = NSScreen.main else { return nil }
        let frame = screen.frame.size
        guard frame.width >= 640, frame.height >= 480 else { return nil }
        var w = Int(frame.width.rounded())
        var h = Int(frame.height.rounded())
        w -= w % 2
        h -= h % 2
        return (w, h)
    }

    /// The display's backing scale (2.0 on Retina, 1.0 otherwise).
    static func backingScale() -> CGFloat {
        max(NSScreen.main?.backingScaleFactor ?? 1.0, 1.0)
    }

    /// Physical screen size divided by the given factor (0.5 = Retina logical resolution).
    static func hiDPIResolution(factor: CGFloat) -> (width: Int, height: Int)? {
        guard let screen = NSScreen.main else { return nil }
        let backing = screen.convertRectToBacking(screen.frame).size
        guard backing.width > 0, backing.height > 0 else { return nil }
        var w = Int((backing.width * factor).rounded())
        var h = Int((backing.height * factor).rounded())
        w -= w % 2
        h -= h % 2
        w = max(640, min(w, Int(backing.width)))
        h = max(480, min(h, Int(backing.height)))
        return (w, h)
    }

    /// Session size when the user picked a HiDPI (scaled) resolution, nil for native.
    static func scaledSessionSize(for pc: PC) -> (width: Int, height: Int)? {
        let mode = pc.fullscreenResolution ?? .native
        switch mode {
        case .native:
            return nil
        case .custom:
            let w = pc.fullscreenWidth ?? 0
            let h = pc.fullscreenHeight ?? 0
            guard w >= 640, h >= 480 else { return nil }
            return (w, h)
        case .half, .threeQuarters:
            guard let screen = NSScreen.main else { return nil }
            let backing = screen.convertRectToBacking(screen.frame).size
            guard backing.width > 0, backing.height > 0 else { return nil }
            let factor: CGFloat = (mode == .half) ? 0.5 : 0.75
            var w = Int((backing.width * factor).rounded())
            var h = Int((backing.height * factor).rounded())
            w -= w % 2
            h -= h % 2
            w = max(640, min(w, Int(backing.width)))
            h = max(480, min(h, Int(backing.height)))
            return (w, h)
        }
    }

    static func buildArguments(
        pc: PC,
        username: String,
        domain: String,
        quality: QualityPreset = .balanced
    ) -> [String] {
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

        let hiDPI = pc.hiDPI ?? false
        let scale = Self.backingScale()

        switch pc.displayMode {
        case .fullScreen:
            args.append("/f")
            if hiDPI {
                // Dynamic resolution: the client reports the logical monitor size
                // (window pixels divided by LANRDP_MONITOR_SCALE), so the server
                // resizes the session in place when the macOS resolution changes.
                args.append("+dynamic-resolution")
            } else if pc.fullscreenFollowScreen ?? true {
                if pc.dynamicResolution {
                    args.append("+dynamic-resolution")
                }
            } else {
                // Run the session at the configured resolution and let the client
                // scale it up to the screen (Windows apps that ignore DPI then
                // look normal).
                let w = max(pc.width, 640)
                let h = max(pc.height, 480)
                args.append("/smart-sizing:\(w)x\(h)")
            }
        case .fitWindow:
            if hiDPI {
                // Window size stays in points; the session is the logical size
                // (dynamic resolution reports window pixels / scale).
                args.append("/w:\(max(Int((Double(max(pc.width, 640)) * scale).rounded()), 640))")
                args.append("/h:\(max(Int((Double(max(pc.height, 480)) * scale).rounded()), 480))")
                args.append("+dynamic-resolution")
            } else {
                args.append("/w:\(max(pc.width, 640))")
                args.append("/h:\(max(pc.height, 480))")
            }
            if !hiDPI, pc.dynamicResolution {
                args.append("+dynamic-resolution")
            }
        case .fixedSize:
            if hiDPI {
                args.append("/w:\(max(Int((Double(max(pc.width, 640)) * scale).rounded()), 640))")
                args.append("/h:\(max(Int((Double(max(pc.height, 480)) * scale).rounded()), 480))")
                args.append("+dynamic-resolution")
            } else {
                args.append("/w:\(max(pc.width, 640))")
                args.append("/h:\(max(pc.height, 480))")
            }
        }

        if hiDPI {
            // The session already runs at the logical size, so Windows should use
            // 100% DPI: the UI then has the same physical size as macOS.
            args.append("/scale:100")
        } else {
            switch pc.scaling {
            case 100:
                // Explicitly force 100% DPI; otherwise an RDS/Windows host may
                // keep its own 150%/200% scaling and show oversized icons.
                args.append("/scale:100")
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

        args.append(contentsOf: qualityArguments(quality))
        // The SDL connection dialog is a small black progress window; the
        // manager app reports errors itself using the FreeRDP log.
        args.append("-sdl-connection-dialog")
        args.append(contentsOf: parseExtraArguments(pc.extraArguments))
        return args
    }

    static func qualityArguments(_ quality: QualityPreset) -> [String] {
        switch quality {
        case .auto, .balanced:
            return ["/network:auto", "/bpp:24"]
        case .high:
            return ["/network:lan", "/bpp:32"]
        case .saver:
            return [
                "/network:wan",
                "/bpp:16",
                "+nsc",
                "-themes",
                "-wallpaper",
                "-menu-anims"
            ]
        }
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
