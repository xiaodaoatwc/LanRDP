import Foundation
import Network

enum QualityPreset: String, Codable, CaseIterable, Identifiable {
    case auto
    case high
    case balanced
    case saver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return L10n.t("自动")
        case .high: return L10n.t("高质量")
        case .balanced: return L10n.t("平衡")
        case .saver: return L10n.t("省流量")
        }
    }

    var detail: String {
        switch self {
        case .auto:
            return L10n.t("连接前探测 RTT 和抖动，自动选择档位；VPN/公网最高使用平衡，不确定时也使用平衡。")
        case .high:
            return L10n.t("32 位色，局域网带宽优先。适合直连局域网。")
        case .balanced:
            return L10n.t("24 位色，自动选择网络类型。适合大多数 VPN/公网连接。")
        case .saver:
            return L10n.t("16 位色，启用 NSC，关闭壁纸、主题和菜单动画。适合高延迟或低带宽。")
        }
    }
}

enum QualityPath: String {
    case lan
    case vpn
    case wan
    case unknown
}

struct QualityResolution {
    let preset: QualityPreset
    let path: QualityPath
    let rttMilliseconds: Double?
    let jitterMilliseconds: Double?
    let successes: Int
    let attempts: Int

    var summary: String {
        let pathText: String
        switch path {
        case .lan: pathText = "LAN"
        case .vpn: pathText = "VPN"
        case .wan: pathText = "WAN"
        case .unknown: pathText = "unknown"
        }
        let rtt = rttMilliseconds.map { String(format: "%.0fms", $0) } ?? "n/a"
        let jitter = jitterMilliseconds.map { String(format: "%.0fms", $0) } ?? "n/a"
        return "\(preset.rawValue), \(pathText), rtt=\(rtt), jitter=\(jitter), \(successes)/\(attempts)"
    }
}

enum NetworkProbe {
    static func resolve(host: String, port: UInt16, attempts: Int = 3) async -> QualityResolution {
        var samples: [ProbeSample] = []

        for _ in 0..<attempts {
            if let sample = await probeOnce(host: host, port: port, timeout: 0.8) {
                samples.append(sample)
            }
        }

        let path = pathType(for: host, sample: samples.first)
        guard !samples.isEmpty else {
            return QualityResolution(
                preset: .balanced,
                path: path,
                rttMilliseconds: nil,
                jitterMilliseconds: nil,
                successes: 0,
                attempts: attempts
            )
        }

        let sorted = samples.map(\.rttMilliseconds).sorted()
        let median = sorted[sorted.count / 2]
        let jitter = (sorted.last ?? median) - (sorted.first ?? median)
        let successes = samples.count

        let preset: QualityPreset
        if successes == 1 {
            preset = .saver
        } else if path == .lan && median <= 40 && jitter <= 15 {
            preset = .high
        } else if median <= 90 && jitter <= 30 {
            preset = .balanced
        } else if median <= 150 && jitter <= 40 {
            preset = .balanced
        } else {
            preset = .saver
        }

        return QualityResolution(
            preset: preset,
            path: path,
            rttMilliseconds: median,
            jitterMilliseconds: jitter,
            successes: successes,
            attempts: attempts
        )
    }

    private static func probeOnce(host: String, port: UInt16, timeout: TimeInterval) async -> ProbeSample? {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.lanrdp.network-probe")
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .tcp
            )
            let state = ProbeCompletion(continuation: continuation)
            let start = DispatchTime.now().uptimeNanoseconds

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    let path = connection.currentPath
                    let sample = ProbeSample(
                        rttMilliseconds: elapsed,
                        usesTunnel: path?.usesInterfaceType(.other) ?? false,
                        usesWiFi: path?.usesInterfaceType(.wifi) ?? false,
                        usesWired: path?.usesInterfaceType(.wiredEthernet) ?? false,
                        usesCellular: path?.usesInterfaceType(.cellular) ?? false
                    )
                    state.finish(value: sample, connection: connection)
                case .failed, .cancelled:
                    state.finish(value: nil, connection: connection)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                state.finish(value: nil, connection: connection)
            }
        }
    }

    private static func pathType(for host: String, sample: ProbeSample?) -> QualityPath {
        guard isPrivateHost(host) else { return .wan }
        guard let sample else { return .unknown }
        if sample.usesTunnel { return .vpn }
        if sample.usesWiFi || sample.usesWired { return .lan }
        if sample.usesCellular { return .wan }
        return .unknown
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            return false
        }
        defer { freeaddrinfo(result) }

        var pointer: UnsafeMutablePointer<addrinfo>? = first
        while let current = pointer {
            let info = current.pointee
            if let address = info.ai_addr {
                if info.ai_family == AF_INET {
                    let sockaddr = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        $0.pointee
                    }
                    var ip = sockaddr.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &ip, &buffer, socklen_t(buffer.count)) != nil {
                        if isPrivateIPv4(String(cString: buffer)) {
                            return true
                        }
                    }
                } else if info.ai_family == AF_INET6 {
                    let sockaddr = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        $0.pointee
                    }
                    var ip = sockaddr.sin6_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    if inet_ntop(AF_INET6, &ip, &buffer, socklen_t(buffer.count)) != nil {
                        if isPrivateIPv6(String(cString: buffer)) {
                            return true
                        }
                    }
                }
            }
            pointer = info.ai_next
        }
        return false
    }

    private static func isPrivateIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 127 { return true }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
        return false
    }

    private static func isPrivateIPv6(_ ip: String) -> Bool {
        let lower = ip.lowercased()
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("fe80:") {
            return true
        }
        if lower.hasPrefix("::ffff:") {
            return isPrivateIPv4(String(lower.dropFirst(7)))
        }
        return false
    }
}

private struct ProbeSample {
    let rttMilliseconds: Double
    let usesTunnel: Bool
    let usesWiFi: Bool
    let usesWired: Bool
    let usesCellular: Bool
}

private final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<ProbeSample?, Never>

    init(continuation: CheckedContinuation<ProbeSample?, Never>) {
        self.continuation = continuation
    }

    func finish(value: ProbeSample?, connection: NWConnection) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        connection.cancel()
        continuation.resume(returning: value)
    }
}
