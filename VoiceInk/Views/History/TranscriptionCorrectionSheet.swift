import SwiftUI
import AppKit
import SwiftData

struct TranscriptionCorrectionSheet: View {
    let transcription: Transcription
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var draft: String
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var replacementTarget = ""
    @State private var selectionUpdate: TranscriptionTextSelectionUpdate?
    @State private var errorMessage: String?

    init(transcription: Transcription, onDismiss: @escaping () -> Void) {
        self.transcription = transcription
        self.onDismiss = onDismiss
        _draft = State(initialValue: transcription.preferredText)
    }

    private var selectedText: String {
        let string = draft as NSString
        guard NSMaxRange(selectedRange) <= string.length else { return "" }
        return string.substring(with: selectedRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedRuleRange: NSRange {
        let string = draft as NSString
        guard NSMaxRange(selectedRange) <= string.length else { return NSRange(location: 0, length: 0) }
        let rawSelection = string.substring(with: selectedRange)
        let leadingWhitespace = rawSelection.prefix(while: { $0.isWhitespace }).utf16.count
        let trailingWhitespace = String(rawSelection.reversed().prefix(while: { $0.isWhitespace })).utf16.count
        let length = max(0, rawSelection.utf16.count - leadingWhitespace - trailingWhitespace)
        return NSRange(location: selectedRange.location + leadingWhitespace, length: length)
    }

    private var canTeach: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canReplace: Bool {
        canTeach && !replacementTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Correct Transcription")
                        .font(.headline)
                    Text("Edit the text, or teach Quill how to recognize selected words.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            TranscriptionPlainTextEditor(
                text: $draft,
                selectedRange: $selectedRange,
                selectionUpdate: selectionUpdate
            )
            .frame(minHeight: 240)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Teach Selection")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    Button("Add Selection to Vocabulary", action: addSelectionToVocabulary)
                        .buttonStyle(.bordered)
                        .disabled(!canTeach)
                    TextField("Replacement", text: $replacementTarget)
                        .textFieldStyle(.roundedBorder)
                    Button("Always Replace Selection", action: addSelectionReplacement)
                        .buttonStyle(.bordered)
                        .disabled(!canReplace)
                }
                Text("Rules affect future local dictation only. Existing transcripts stay unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Status.error)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onDismiss)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 680)
    }

    private func addSelectionToVocabulary() {
        let selection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return }

        do {
            let existing = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
            if let error = DictionaryService.addVocabularyWords(selection, existing: existing, context: modelContext) {
                errorMessage = error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSelectionReplacement() {
        let selection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty, !replacement.isEmpty else { return }

        do {
            let existing = try modelContext.fetch(FetchDescriptor<WordReplacement>())
            if let error = DictionaryService.addWordReplacement(
                original: selection,
                replacement: replacement,
                existing: existing,
                context: modelContext
            ) {
                errorMessage = error
                return
            }

            selectionUpdate = TranscriptionTextSelectionUpdate(range: selectedRuleRange, text: replacement)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let correctedText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousText = transcription.correctedText
        transcription.correctedText = correctedText.isEmpty ? nil : correctedText

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCorrected, object: transcription)
            onDismiss()
        } catch {
            modelContext.rollback()
            transcription.correctedText = previousText
            errorMessage = String(format: String(localized: "Failed to save correction: %@"), error.localizedDescription)
        }
    }
}

struct TranscriptionTextSelectionUpdate: Equatable {
    let id = UUID()
    let range: NSRange
    let text: String

    init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }
}

private struct TranscriptionPlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let selectionUpdate: TranscriptionTextSelectionUpdate?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = AppTheme.NativeText.primary
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }

        if let selectionUpdate,
           context.coordinator.appliedSelectionUpdateID != selectionUpdate.id {
            let current = textView.string as NSString
            guard NSMaxRange(selectionUpdate.range) <= current.length else { return }
            let mutable = NSMutableString(string: textView.string)
            mutable.replaceCharacters(in: selectionUpdate.range, with: selectionUpdate.text)
            textView.string = mutable as String
            let updatedRange = NSRange(
                location: selectionUpdate.range.location,
                length: selectionUpdate.text.utf16.count
            )
            textView.setSelectedRange(updatedRange)
            context.coordinator.parent.text = textView.string
            context.coordinator.parent.selectedRange = updatedRange
            context.coordinator.appliedSelectionUpdateID = selectionUpdate.id
            return
        }

        if NSMaxRange(selectedRange) > (textView.string as NSString).length {
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        } else {
            textView.setSelectedRange(selectedRange)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranscriptionPlainTextEditor
        var appliedSelectionUpdateID: UUID?

        init(_ parent: TranscriptionPlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }
    }
}
