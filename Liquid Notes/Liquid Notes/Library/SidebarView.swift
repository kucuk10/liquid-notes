import SwiftUI
import SwiftData

/// The first column: smart collections, notepad types and folders.
struct SidebarView: View {
    @Binding var selection: LibraryCollection?
    /// Shared with the notepad list, which shows the results.
    @Binding var searchText: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query private var notepads: [Notepad]

    @State private var isAddingFolder = false
    @State private var newFolderName = ""
    @State private var folderBeingRenamed: Folder?
    @State private var renameText = ""
    @State private var folderPendingDeletion: Folder?

    var body: some View {
        List(selection: $selection) {
            Section {
                row(for: .recents)
                row(for: .all)
            }

            Section("Types") {
                ForEach(NotepadType.allCases) { type in
                    row(for: .type(type))
                }
            }

            Section("Folders") {
                ForEach(folders) { folder in
                    row(for: .folder(folder))
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                renameText = folder.name
                                folderBeingRenamed = folder
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                folderPendingDeletion = folder
                            }
                        }
                }

                Button {
                    newFolderName = ""
                    isAddingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        .navigationTitle("Liquid Notes")
        // The sidebar is the first screen on iPhone, so search starts here too. Results appear in
        // the notepad list: live beside the sidebar on iPad and Mac, or after pressing Search on iPhone.
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search all notepads"
        )
        .onSubmit(of: .search) {
            if selection == nil { selection = .all }
        }
        .onChange(of: searchText) { _, text in
            if selection == nil && !text.isEmpty && horizontalSizeClass == .regular {
                selection = .all
            }
        }
        .alert("New Folder", isPresented: $isAddingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createFolder() }
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Folders can hold notes, notebooks and canvases together.")
        }
        .alert("Rename Folder", isPresented: isRenaming) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { folderBeingRenamed?.name = name }
            }
        }
        .confirmationDialog(
            "Delete “\(folderPendingDeletion?.name ?? "")”?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Folder and Contents", role: .destructive) { deletePendingFolder() }
        } message: {
            let count = folderPendingDeletion?.notepads?.count ?? 0
            Text("The \(count) notepads in this folder will be deleted from all your devices.")
        }
    }

    private func row(for collection: LibraryCollection) -> some View {
        NavigationLink(value: collection) {
            Label(collection.title, systemImage: collection.systemImageName)
        }
        .badge(notepads.filter(collection.contains).count)
    }

    private var isRenaming: Binding<Bool> {
        Binding { folderBeingRenamed != nil } set: { if !$0 { folderBeingRenamed = nil } }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding { folderPendingDeletion != nil } set: { if !$0 { folderPendingDeletion = nil } }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folder = Folder(name: name)
        modelContext.insert(folder)
        try? modelContext.save()
        selection = .folder(folder)
    }

    private func deletePendingFolder() {
        guard let folder = folderPendingDeletion else { return }
        if selection == .folder(folder) { selection = .all }
        modelContext.delete(folder)
        folderPendingDeletion = nil
    }
}
