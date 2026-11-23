import SwiftUI

/// Chooses a title, page size and paper style before creating a notebook.
struct NotebookSetupSheet: View {
    var onCreate: (_ title: String, _ size: PaperSize, _ style: PaperStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var size = NotebookSetupSheet.regionalDefaultSize
    @State private var style = PaperStyle.ruled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("Untitled Notebook"))
                }

                Section("Page Size") {
                    Picker("Page Size", selection: $size) {
                        ForEach(PaperSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                Section("Paper") {
                    Picker("Paper", selection: $style) {
                        ForEach(PaperStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.systemImageName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    PaperBackground(style: style, pageSize: size.size)
                        .background(.white)
                        .aspectRatio(size.size.width / size.size.height, contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(.rect(cornerRadius: 3))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        onCreate(trimmed.isEmpty ? String(localized: "Untitled Notebook") : trimmed, size, style)
                        dismiss()
                    }
                }
            }
        }
    }

    /// Letter is standard in North America and a few other regions; A4 everywhere else.
    static var regionalDefaultSize: PaperSize {
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "GT", "CR", "PR"]
        let region = Locale.current.region?.identifier ?? "US"
        return letterRegions.contains(region) ? .letter : .a4
    }
}

#Preview {
    NotebookSetupSheet { _, _, _ in }
}
