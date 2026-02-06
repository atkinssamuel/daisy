import SwiftUI
import AppKit

// MARK: - Terminal Text View (NSViewRepresentable)
// Wraps NSTextView for rendering NSAttributedString with ANSI colors on a black background

struct TerminalTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.verticalScrollElasticity = .none

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .black
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isRichText = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Watch for user scrolling

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // Update content

        textView.textStorage?.setAttributedString(attributedString)

        // Auto-scroll if sticky mode is on

        if context.coordinator.stickyScroll {
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var textView: NSTextView?
        var scrollView: NSScrollView?
        var stickyScroll = true
        var isAutoScrolling = false

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = scrollView,
                  let docView = scrollView.documentView else { return }

            // Skip if we triggered this scroll programmatically

            if isAutoScrolling { return }

            let clipView = scrollView.contentView
            let docHeight = docView.frame.height
            let clipHeight = clipView.bounds.height
            let scrollY = clipView.bounds.origin.y
            let distanceFromBottom = docHeight - scrollY - clipHeight

            // If user scrolled to bottom (within 50px), enable sticky

            if distanceFromBottom < 50 {
                stickyScroll = true
            } else {
                stickyScroll = false
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
