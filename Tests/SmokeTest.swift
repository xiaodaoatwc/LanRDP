import Foundation

@main
struct SmokeTest {
    static func main() async {
        var failures: [String] = []

        var pc = PC(name: "Office", host: "192.168.1.10", port: 3389)
        pc.displayMode = .fitWindow
        pc.width = 1600
        pc.height = 1000
        pc.scaling = 200
        pc.clipboard = true
        pc.audio = false
        pc.shareFolder = true
        pc.folderPath = "/Users/linc/Downloads"
        pc.certificatePolicy = .ignore
        let credential = Credential(name: "Office", username: "linc", domain: "DESKTOP-ABC")
        let args = RDPLauncher.buildArguments(pc: pc, username: credential.username, domain: credential.domain)

        func expect(_ condition: Bool, _ message: String) {
            if condition {
                print("PASS  \(message)")
            } else {
                failures.append(message)
                print("FAIL  \(message)")
            }
        }

        expect(args.contains("/v:192.168.1.10:3389"), "server argument")
        expect(args.contains("/u:linc"), "username argument")
        expect(args.contains("/d:DESKTOP-ABC"), "domain argument")
        expect(args.contains("/from-stdin:force"), "password via stdin")
        expect(args.contains("/cert:ignore"), "certificate policy")
        expect(args.contains("/w:1600") && args.contains("/h:1000"), "window size")
        expect(args.contains("/scale-desktop:200"), "retina scaling")
        var pc100 = pc
        pc100.scaling = 100
        let args100 = RDPLauncher.buildArguments(pc: pc100, username: "linc", domain: "")
        expect(args100.contains("/scale:100"), "explicit 100% DPI")

        expect(pc.qualityPreset == .auto, "new PCs default to auto quality")
        let highArgs = RDPLauncher.buildArguments(pc: pc, username: "linc", domain: "", quality: .high)
        expect(highArgs.contains("/network:lan"), "high quality uses LAN network")
        expect(highArgs.contains("/bpp:32"), "high quality uses 32 bpp")
        let balancedArgs = RDPLauncher.buildArguments(pc: pc, username: "linc", domain: "", quality: .balanced)
        expect(balancedArgs.contains("/network:auto"), "balanced quality uses auto network")
        expect(balancedArgs.contains("/bpp:24"), "balanced quality uses 24 bpp")
        let saverArgs = RDPLauncher.buildArguments(pc: pc, username: "linc", domain: "", quality: .saver)
        expect(saverArgs.contains("/network:wan"), "saver uses WAN network")
        expect(saverArgs.contains("/bpp:16"), "saver uses 16 bpp")
        expect(saverArgs.contains("+nsc"), "saver enables NSC")
        expect(args.contains("/drive:MacShare,/Users/linc/Downloads"), "folder sharing")
        expect(args.contains("-sound"), "audio disabled")
        expect(args.contains("-sdl-connection-dialog"), "SDL connection dialog disabled")
        expect(!args.contains(where: { $0.hasPrefix("/p:") }), "password not in argv")

        let parsed = RDPLauncher.parseExtraArguments("/sec:nla \"/gfx:AVC444\"")
        expect(parsed == ["/sec:nla", "/gfx:AVC444"], "extra argument parser")

        let directArgs = RDPLauncher.buildArguments(pc: pc, username: "directuser", domain: "")
        expect(directArgs.contains("/u:directuser"), "direct username argument")
        expect(!directArgs.contains("/d:"), "empty direct domain omitted")

        var pc150 = pc
        pc150.scaling = 150
        let args150 = RDPLauncher.buildArguments(pc: pc150, username: "linc", domain: "")
        expect(args150.contains("/scale-desktop:150"), "150% desktop scaling")
        expect(args150.contains("/scale-device:140"), "150% nearest device scaling")

        var adminPC = pc
        adminPC.adminSession = true
        let adminArgs = RDPLauncher.buildArguments(pc: adminPC, username: "administrator", domain: "")
        expect(adminArgs.contains("/admin"), "admin session argument")

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanRDP-Smoke-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let vaultURL = temp.appendingPathComponent("vault.json")
        let vaultID = UUID()
        let vault = PasswordVault(url: vaultURL)
        vault.setPassword("vault-secret", for: vaultID)
        expect(vault.password(for: vaultID) == "vault-secret", "password vault round trip")
        let attrs = try? FileManager.default.attributesOfItem(atPath: vaultURL.path)
        let permissions = (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        expect(permissions == 0o600, "password vault permissions are 0600")

        let store = await MainActor.run { Store(baseDirectory: temp) }
        let binary = "/Users/linc/Documents/deepseek-harness/default-workspace/lanrdp/.build/build/freerdp-sdl/client/SDL/SDL3/sdl-freerdp"

        let mostVisited = await MainActor.run { () -> [String] in
            var frequent = PC(name: "Frequent", host: "192.168.1.20")
            frequent.visitCount = 7
            frequent.lastConnected = Date()
            var recent = PC(name: "Recent", host: "192.168.1.21")
            recent.visitCount = 3
            recent.lastConnected = Date()
            let never = PC(name: "Never", host: "192.168.1.22")
            store.addPC(frequent)
            store.addPC(recent)
            store.addPC(never)
            return store.mostVisitedPCs.map(\.name)
        }
        expect(mostVisited == ["Frequent", "Recent"], "most visited sorts by visit count and excludes never-visited PCs")

        let directPending = await MainActor.run { () -> PasswordPrompt? in
            let direct = PC(name: "Direct", host: "192.168.1.11")
            store.addPC(direct)
            store.connect(direct)
            return store.pendingPassword
        }
        expect(directPending?.isDirectLogin == true, "direct login prompts without a credential")
        await MainActor.run { store.pendingPassword = nil }

        await MainActor.run {
            store.settings.binaryPath = binary
            var loopback = PC(name: "Loopback", host: "127.0.0.1", port: 3389)
            loopback.certificatePolicy = .ignore
            loopback.displayMode = .fixedSize
            store.launch(pc: loopback, username: credential.username, domain: credential.domain, password: "test")
        }

        try? await Task.sleep(nanoseconds: 6_000_000_000)

        // Verify the askpass helper is wired up and returns the password.
        let fakeBinary = temp.appendingPathComponent("fake-rdp.sh")
        let askpassOutput = temp.appendingPathComponent("askpass-output.txt")
        let fakeScript = """
        #!/bin/sh
        "$FREERDP_ASKPASS" "FreeRDP authentication" > "\(askpassOutput.path)"
        exit 0
        """
        try? fakeScript.write(to: fakeBinary, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeBinary.path)
        await MainActor.run {
            store.settings.binaryPath = fakeBinary.path
            let fakePC = PC(name: "Askpass", host: "127.0.0.1")
            store.launch(pc: fakePC, username: "u", domain: "", password: "askpass-secret")
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let askpassText = (try? String(contentsOf: askpassOutput, encoding: .utf8)) ?? ""
        expect(askpassText == "askpass-secret", "askpass helper returns the saved password")

        let state = await MainActor.run {
            let cancelled = store.looksLikeFailure("ERRCONNECT_CONNECT_CANCELLED")
            let failed = store.looksLikeFailure("ERRCONNECT_CONNECT_FAILED")
            return (
                store.activeSessionIDs.count,
                store.lastError?.title,
                store.pcs.count,
                cancelled,
                failed,
                store.lastError?.message ?? ""
            )
        }
        expect(state.3 == false, "normal user cancellation is not a failure")
        expect(state.4 == true, "real connection failure is detected")
        expect(state.5.count < 300, "failure alert stays concise")
        expect(!state.5.contains("原始日志"), "failure alert does not dump the raw log")

        let licenseState = await MainActor.run { () -> (Bool, AppAlert) in
            let log = "ERROR rdp_client_connect_license: license connection sequence aborted. ERRCONNECT_CONNECT_TRANSPORT_FAILED"
            return (store.looksLikeFailure(log), store.failureAlert(displayName: "HNK-SV-MES103", port: 3389, log: log))
        }
        expect(licenseState.0, "license/transport failure is detected")
        expect(licenseState.1.message.contains("许可"), "license failure has a specific short message")
        expect(licenseState.1.message.count < 300, "license alert stays concise")
        expect(state.0 == 0, "session cleaned up after failure")
        expect(state.1 != nil, "connection failure surfaced as an alert")
        print("lastError: \(state.1 ?? "nil")")

        if failures.isEmpty {
            print("SMOKE OK")
        } else {
            print("SMOKE FAILED: \(failures.count)")
            exit(1)
        }
    }
}
