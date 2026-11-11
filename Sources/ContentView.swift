import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: SidebarItem? = .all
    @State private var showAddPC = false
    @State private var editingPC: PC?
    @State private var showAddGroup = false
    @State private var renamingGroup: PCGroup?
    @State private var deletingPC: PC?
    @State private var deletingGroup: PCGroup?
    @State private var selectedPCID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                onAddGroup: { showAddGroup = true },
                onRenameGroup: { renamingGroup = $0 },
                onDeleteGroup: { deletingGroup = $0 }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showAddPC = true
                } label: {
                    Label("添加 PC", systemImage: "plus")
                }
                .help("添加一台远程电脑")

                Button {
                    showAddGroup = true
                } label: {
                    Label("添加分组", systemImage: "folder.badge.plus")
                }
                .help("新建分组")

                Button {
                    selection = .credentials
                } label: {
                    Label("凭据", systemImage: "key")
                }
                .help("管理共享凭据")

                Button {
                    selection = .settings
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .help("设置")
            }
        }
        .sheet(isPresented: $showAddPC) {
            PCEditorView(mode: .add) { pc in
                store.addPC(pc)
            }
        }
        .sheet(item: $editingPC) { pc in
            PCEditorView(mode: .edit(pc)) { updated in
                store.updatePC(updated)
            }
        }
        .sheet(isPresented: $showAddGroup) {
            GroupNameEditor(title: "新建分组", initialName: "") { name in
                if let group = store.addGroup(named: name) {
                    selection = .group(group.id)
                }
            }
        }
        .sheet(item: $renamingGroup) { group in
            GroupNameEditor(title: "重命名分组", initialName: group.name) { name in
                store.renameGroup(group, to: name)
            }
        }
        .sheet(item: $store.pendingPassword) { prompt in
            PasswordPromptView(
                pc: prompt.pc,
                credential: prompt.credential,
                username: prompt.username,
                domain: prompt.domain
            ) { username, domain, password, save in
                store.connect(
                    pc: prompt.pc,
                    credential: prompt.credential,
                    username: username,
                    domain: domain,
                    password: password,
                    savePassword: save
                )
                store.pendingPassword = nil
            } onCancel: {
                store.pendingPassword = nil
            }
        }
        .alert(item: $store.lastError) { alert in
            if alert.showLogs {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("好")),
                    secondaryButton: .default(Text("查看日志")) {
                        store.openLogsFolder()
                    }
                )
            } else {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
        .confirmationDialog(
            "删除电脑？",
            isPresented: Binding(
                get: { deletingPC != nil },
                set: { if !$0 { deletingPC = nil } }
            ),
            presenting: deletingPC
        ) { pc in
            Button("删除", role: .destructive) {
                store.deletePC(pc)
                deletingPC = nil
            }
            Button("取消", role: .cancel) { deletingPC = nil }
        } message: { pc in
            Text(L10n.f("“%@”的连接配置会被删除，已保存的凭据不会删除。", pc.name.isEmpty ? pc.host : pc.name))
        }
        .confirmationDialog(
            "删除分组？",
            isPresented: Binding(
                get: { deletingGroup != nil },
                set: { if !$0 { deletingGroup = nil } }
            ),
            presenting: deletingGroup
        ) { group in
            Button("删除", role: .destructive) {
                store.deleteGroup(group)
                if case .group(let id) = selection, id == group.id {
                    selection = .all
                }
                deletingGroup = nil
            }
            Button("取消", role: .cancel) { deletingGroup = nil }
        } message: { group in
            Text(L10n.f("分组“%@”会被删除，里面的电脑会移到“所有电脑”，不会删除电脑本身。", group.name))
        }
        .onChange(of: selection) { _, _ in
            selectedPCID = nil
        }
        .onChange(of: store.settings.showMostVisited) { _, visible in
            if !visible, selection == .mostVisited {
                selection = .all
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .all:
            PCListContent(
                title: L10n.t("所有电脑"),
                subtitle: L10n.t("局域网 / 广域网远程桌面"),
                pcs: store.pcs,
                onAdd: { showAddPC = true },
                onConnect: { store.connect($0) },
                onEdit: { editingPC = $0 },
                onDelete: { deletingPC = $0 },
                selectedPCID: $selectedPCID
            )
        case .mostVisited:
            if store.mostVisitedPCs.isEmpty {
                ContentUnavailableView(
                    "还没有访问记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("连接一台电脑后，这里会显示最常访问的电脑。")
                )
            } else {
                PCListContent(
                    title: L10n.t("最常访问"),
                    subtitle: L10n.t("按访问频率排序"),
                    pcs: store.mostVisitedPCs,
                    onAdd: { showAddPC = true },
                    onConnect: { store.connect($0) },
                    onEdit: { editingPC = $0 },
                    onDelete: { deletingPC = $0 },
                    selectedPCID: $selectedPCID,
                    preserveOrder: true
                )
            }
        case .ungrouped:
            if store.ungroupedPCs.isEmpty {
                ContentUnavailableView(
                    "没有未分组的电脑",
                    systemImage: "tray",
                    description: Text("所有电脑都已经分配到分组。")
                )
            } else {
                PCListContent(
                    title: L10n.t("未分组"),
                    subtitle: L10n.t("未分组电脑"),
                    pcs: store.ungroupedPCs,
                    onAdd: { showAddPC = true },
                    onConnect: { store.connect($0) },
                    onEdit: { editingPC = $0 },
                    onDelete: { deletingPC = $0 },
                    selectedPCID: $selectedPCID
                )
            }
        case .group(let id):
            if let group = store.group(for: id) {
                PCListContent(
                    title: group.name,
                    subtitle: L10n.t("分组"),
                    pcs: store.pcs.filter { $0.groupID == id },
                    onAdd: { showAddPC = true },
                    onConnect: { store.connect($0) },
                    onEdit: { editingPC = $0 },
                    onDelete: { deletingPC = $0 },
                    selectedPCID: $selectedPCID
                )
            } else {
                ContentUnavailableView("分组不存在", systemImage: "folder.badge.questionmark")
            }
        case .credentials:
            CredentialsView()
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView(
                "选择左侧的项目",
                systemImage: "sidebar.left",
                description: Text("查看所有电脑、分组、凭据或设置。")
            )
        }
    }
}
