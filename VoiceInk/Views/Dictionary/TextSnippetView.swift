import SwiftData
import SwiftUI

struct TextSnippetView: View {
    @Query private var textSnippets: [TextSnippet]
    @Environment(\.modelContext) private var modelContext
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var editingSnippet: TextSnippet?
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var sortedSnippets: [TextSnippet] {
        textSnippets.sorted {
            let triggerOrder = $0.trigger.localizedCaseInsensitiveCompare($1.trigger)
            if triggerOrder != .orderedSame {
                return triggerOrder == .orderedAscending
            }
            let expansionOrder = $0.expansion.localizedCaseInsensitiveCompare($1.expansion)
            if expansionOrder != .orderedSame {
                return expansionOrder == .orderedAscending
            }
            return $0.dateAdded < $1.dateAdded
        }
    }

    private var canSave: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addSection

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Snippets (\(textSnippets.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                if sortedSnippets.isEmpty {
                    Text("No text snippets yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedSnippets) { snippet in
                            TextSnippetRow(
                                trigger: snippet.trigger,
                                expansion: snippet.expansion,
                                isEnabled: snippet.isEnabled,
                                onEdit: { editingSnippet = snippet },
                                onDelete: { remove(snippet) },
                                onEnabledChange: { setEnabled(snippet, isEnabled: $0) }
                            )

                            if snippet.id != sortedSnippets.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: isEditingSnippet) {
            if let editingSnippet {
                EditTextSnippetSheet(
                    snippet: editingSnippet,
                    existingSnippets: textSnippets,
                    modelContext: modelContext
                )
            }
        }
        .alert("Text Snippets", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Enter trigger", text: $trigger)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            Text("Expansion")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextEditor(text: $expansion)
                .font(.system(size: 13))
                .frame(height: 90)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AppTheme.Surface.window.opacity(0.4))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                        .stroke(AppTheme.Border.control, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if expansion.isEmpty {
                        Text("Enter expansion")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Spacer()
                AddIconButton(
                    helpText: "Add text snippet",
                    isDisabled: !canSave,
                    action: add
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var isEditingSnippet: Binding<Bool> {
        Binding(
            get: { editingSnippet != nil },
            set: { isPresented in
                if !isPresented {
                    editingSnippet = nil
                }
            }
        )
    }

    private func add() {
        if let error = DictionaryService.addTextSnippet(
            trigger: trigger,
            expansion: expansion,
            existing: textSnippets,
            context: modelContext
        ) {
            present(error)
            return
        }
        trigger = ""
        expansion = ""
    }

    private func setEnabled(_ snippet: TextSnippet, isEnabled: Bool) {
        if let error = DictionaryService.updateTextSnippet(
            snippet,
            trigger: snippet.trigger,
            expansion: snippet.expansion,
            isEnabled: isEnabled,
            existing: textSnippets,
            context: modelContext
        ) {
            present(error)
        }
    }

    private func remove(_ snippet: TextSnippet) {
        modelContext.delete(snippet)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            present(String(format: String(localized: "Failed to remove text snippet: %@"), error.localizedDescription))
        }
    }

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

private struct EditTextSnippetSheet: View {
    let snippet: TextSnippet
    let existingSnippets: [TextSnippet]
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var trigger: String
    @State private var expansion: String
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(snippet: TextSnippet, existingSnippets: [TextSnippet], modelContext: ModelContext) {
        self.snippet = snippet
        self.existingSnippets = existingSnippets
        self.modelContext = modelContext
        _trigger = State(initialValue: snippet.trigger)
        _expansion = State(initialValue: snippet.expansion)
    }

    private var canSave: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(Divider().opacity(0.5), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trigger")
                            .font(.headline)
                        TextField("Enter trigger", text: $trigger)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Expansion")
                            .font(.headline)
                        TextEditor(text: $expansion)
                            .font(.body)
                            .frame(height: 180)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(AppTheme.Surface.window.opacity(0.4))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                                    .stroke(AppTheme.Border.control, lineWidth: 1)
                            }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 420)
        .alert("Text Snippets", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text("Edit Text Snippet")
                .font(.headline)

            Spacer()

            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppCardBackground(isSelected: false, cornerRadius: 16))
    }

    private func save() {
        if let error = DictionaryService.updateTextSnippet(
            snippet,
            trigger: trigger,
            expansion: expansion,
            existing: existingSnippets,
            context: modelContext
        ) {
            alertMessage = error
            showAlert = true
            return
        }
        dismiss()
    }
}

private struct TextSnippetRow: View {
    let trigger: String
    let expansion: String
    let isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onEnabledChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Enabled", isOn: Binding(
                get: { isEnabled },
                set: onEnabledChange
            ))
            .labelsHidden()
            .accessibilityLabel("Enable text snippet")

            VStack(alignment: .leading, spacing: 4) {
                Text(trigger)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(expansion)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .buttonStyle(.borderless)
            .help("Edit text snippet")
            .accessibilityLabel("Edit text snippet")

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Status.error)
            }
            .buttonStyle(.borderless)
            .help("Remove text snippet")
            .accessibilityLabel("Remove text snippet")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .opacity(isEnabled ? 1 : 0.55)
    }
}
