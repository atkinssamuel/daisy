import SwiftUI
import AppKit

// MARK: - Auto-expanding message input with Enter to submit
struct ExpandingMessageInput: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onEscape: (() -> Void)? = nil

    // Single line height: font size 13 ≈ 16pt line height + 2pt padding = 18
    private let singleLineHeight: CGFloat = 18
    @State private var textHeight: CGFloat = 18

    var body: some View {
        ExpandingTextViewRepresentable(
            text: $text,
            calculatedHeight: $textHeight,
            singleLineHeight: singleLineHeight,
            onSubmit: onSubmit,
            onEscape: onEscape
        )
        .frame(height: max(singleLineHeight, textHeight))
        .onChange(of: text) { newValue in
            if newValue.isEmpty {
                textHeight = singleLineHeight
            }
        }
    }
}

struct ExpandingTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat
    var singleLineHeight: CGFloat
    var onSubmit: () -> Void
    var onEscape: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.insertionPointColor = .white
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.allowsUndo = true
        textView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.singleLineHeight = singleLineHeight

        // Calculate initial height after setup
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExpandingTextViewRepresentable
        weak var textView: NSTextView?
        var singleLineHeight: CGFloat = 18

        init(_ parent: ExpandingTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            // Use single line height as minimum, actual content height otherwise
            let newHeight = textView.string.isEmpty ? singleLineHeight : max(singleLineHeight, usedRect.height)

            if abs(newHeight - parent.calculatedHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.calculatedHeight = newHeight
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSEvent.modifierFlags
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    parent.onSubmit()
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape?()
                return true
            }

            return false
        }
    }
}

// MARK: - Simple styled text editor with character limit
struct StyledTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var height: CGFloat = 80
    var charLimit: Int = 500

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { text },
                set: { newValue in
                    if newValue.count <= charLimit {
                        text = newValue
                    }
                }
            ))
            .font(.system(size: 13))
            .foregroundColor(.white)
            .scrollContentBackground(.hidden)
            .frame(height: height)

            HStack {
                Spacer()
                Text("\(text.count)/\(charLimit)")
                    .font(.system(size: 10))
                    .foregroundColor(text.count >= charLimit ? .orange : .gray)
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color(white: 0.1))
        .cornerRadius(8)
    }
}
