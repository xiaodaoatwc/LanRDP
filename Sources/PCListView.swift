import SwiftUI

struct PCListContent: View {
    @EnvironmentObject private var store: Store

    let title: String
    let subtitle: String
    let pcs: [PC]
    let onAdd: () -> Void
    let onConnect: (PC) -> Void
    let onEdit: (PC) -> Void
    let onDelete: (PC) -> Void

    @State private var searchText = ""

    private var filteredPCs: [PC] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [PC]
        if query.isEmpty {
            filtered = pcs
        } else {
            filtered = pcs.filter { pc in
                pc.name.localizedCaseInsensitiveContains(query)
                    || pc.host.localizedCaseInsensitiveContains(query)
                    || (store.groupName(for: pc.groupID)?.localizedCaseInsensitiveContains(query) ?? false)
                    || (store.credentialName(for: pc)?.localizedCaseInsensitiveContains(query) ?? false)
                    || (pc.username?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return filtered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if pcs.isEmpty {
                emptyState
            } else if filteredPCs.isEmpty {
                ContentUnavailableView(
                    "没有匹配的电脑",
                    systemImage: "magnifyingglass",
                    description: Text("换个名称、IP 或凭据试试。")
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300, maximum: 430), spacing: 16)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(filteredPCs) { pc in
                            PCCard(
                                pc: pc,
                                groupName: store.groupName(for: pc.groupID),
                                credentialName: loginLabel(for: pc),
                                isActive: store.activeSessionIDs.contains(pc.id),
                                onConnect: { onConnect(pc) },
                                onEdit: { onEdit(pc) },
                                onDelete: { onDelete(pc) }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索电脑")
    }

    private func loginLabel(for pc: PC) -> String {
        if let name = store.credentialName(for: pc) {
            return name
        }
        let user = (pc.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? L10n.t("直接输入") : L10n.f("直接：%@", user)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(L10n.f("%ld 台电脑 · %@", pcs.count, subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAdd) {
                Label("添加 PC", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有电脑", systemImage: "desktopcomputer")
        } description: {
            Text("添加一台 Windows 电脑，用 FreeRDP 连接。\n局域网或广域网都可以，不需要 Microsoft 账号。")
        } actions: {
            Button("添加第一台 PC", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct PCCard: View {
    let pc: PC
    let groupName: String?
    let credentialName: String?
    let isActive: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var displayName: String {
        pc.name.isEmpty ? pc.host : pc.name
    }

    private var displaySummary: String {
        switch pc.displayMode {
        case .fullScreen:
            return L10n.f("全屏 · %ld%%", pc.scaling)
        case .fitWindow:
            return L10n.f("%ld×%ld · 动态 · %ld%%", pc.width, pc.height, pc.scaling)
        case .fixedSize:
            return L10n.f("%ld×%ld · 固定 · %ld%%", pc.width, pc.height, pc.scaling)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(pc.host):\(pc.port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("编辑…", action: onEdit)
                    Divider()
                    Button("删除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多")
            }

            HStack(spacing: 14) {
                if let groupName {
                    Label(groupName, systemImage: "folder")
                        .lineLimit(1)
                }
                if let credentialName {
                    Label(
                        credentialName,
                        systemImage: (credentialName.hasPrefix("直接") || credentialName.hasPrefix("Direct"))
                            ? "person" : "key"
                    )
                    .lineLimit(1)
                }
                if groupName == nil && credentialName == nil {
                    Text("未分组 · 无凭据")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(displaySummary, systemImage: "rectangle.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if pc.shareFolder {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("共享本地文件夹")
                }

                Spacer(minLength: 4)

                Button(action: onConnect) {
                    Label(
                        LocalizedStringKey(isActive ? "连接中" : "连接"),
                        systemImage: isActive ? "hourglass" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isActive)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(count: 2) {
            if !isActive { onConnect() }
        }
        .contextMenu {
            Button("连接", action: onConnect).disabled(isActive)
            Button("编辑…", action: onEdit)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}
