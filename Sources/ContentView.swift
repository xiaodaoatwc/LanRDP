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
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
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
            Text("“\(pc.name.isEmpty ? pc.host : pc.name)”的连接配置会被删除，已保存的凭据不会删除。")
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
            Text("分组“\(group.name)”会被删除，里面的电脑会移到“所有电脑”，不会删除电脑本身。")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .all:
            PCListContent(
                title: "所有电脑",
                subtitle: "局域网 / 广域网远程桌面",
                pcs: store.pcs,
                onAdd: { showAddPC = true },
                onConnect: { store.connect($0) },
                onEdit: { editingPC = $0 },
                onDelete: { deletingPC = $0 }
            )
        case .group(let id):
            if let group = store.group(for: id) {
                PCListContent(
                    title: group.name,
                    subtitle: "分组",
                    pcs: store.pcs.filter { $0.groupID == id },
                    onAdd: { showAddPC = true },
                    onConnect: { store.connect($0) },
                    onEdit: { editingPC = $0 },
                    onDelete: { deletingPC = $0 }
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
