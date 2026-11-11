import SwiftUI
import UniformTypeIdentifiers

enum PCDragPayload {
    static let prefix = "lanrdp-pc:"

    static func string(for id: UUID) -> String {
        "\(prefix)\(id.uuidString)"
    }

    static func id(from string: String) -> UUID? {
        guard string.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(string.dropFirst(prefix.count)))
    }
}

struct PCDropTarget: ViewModifier {
    let onDrop: (UUID) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(isTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
            .onDrop(of: [UTType.plainText], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let value = object as? NSString,
                          let id = PCDragPayload.id(from: value as String) else {
                        return
                    }
                    DispatchQueue.main.async {
                        onDrop(id)
                    }
                }
                return true
            }
    }
}
