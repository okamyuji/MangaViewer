import AppKit
import SwiftUI

struct KeyboardHandlerView: NSViewRepresentable {
    let onKeyDown: (UInt16) -> Bool

    func makeNSView(context _: Context) -> KeyboardNSView {
        let view = KeyboardNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyboardNSView, context _: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

final class KeyboardNSView: NSView {
    var onKeyDown: ((UInt16) -> Bool)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Remove existing monitor
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Set up local event monitor for key events
        if window != nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if let handler = self?.onKeyDown, handler(event.keyCode) {
                    return nil // Event handled, don't propagate
                }
                return event // Pass event along
            }
            window?.makeFirstResponder(self)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            removeMonitor()
        }
    }

    private func removeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        // Note: localMonitor cleanup handled in viewWillMove(toWindow:)
    }

    override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown, handler(event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }
}
