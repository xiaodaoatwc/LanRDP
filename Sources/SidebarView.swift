import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: Store
    @Binding var selection: SidebarItem?
    let onAddGroup: () -> Void
    let onRenameGroup: (PCGroup) -> Void
    let onDeleteGroup: (PCGroup) -> Void

    var body: some View {
        List(selection: $selection) {
            Section("电脑") {
                Label("所有电脑", systemImage: "desktopcomputer")
                    .badge(store.pcs.count)
                    .tag(SidebarItem.all)

                if store.settings.showMostVisited {
                    Label("最常访问", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarItem.mostVisited)
                }

                ForEach(store.groups) { group in
                    Label(group.name, systemImage: "folder")
                        .badge(store.pcs.filter { $0.groupID == group.id }.count)
                        .tag(SidebarItem.group(group.id))
                        .modifier(PCDropTarget { pcID in
                            store.movePC(id: pcID, to: group.id)
                        })
                        .contextMenu {
                            Button("重命名…") { onRenameGroup(group) }
                            Button("删除分组", role: .destructive) { onDeleteGroup(group) }
                        }
                }

                Label("未分组", systemImage: "tray")
                    .badge(store.ungroupedPCs.count)
                    .tag(SidebarItem.ungrouped)
                    .modifier(PCDropTarget { pcID in
                        store.movePC(id: pcID, to: nil)
                    })
            }

            Section("管理") {
                Label("凭据", systemImage: "key")
                    .badge(store.credentials.count)
                    .tag(SidebarItem.credentials)
                Label("设置", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button(action: onAddGroup) {
                    Label("新建分组", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.bar)
        }
        .navigationTitle("LanRDP")
    }
}
