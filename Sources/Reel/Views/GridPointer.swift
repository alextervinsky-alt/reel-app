#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// Lifted or not, for one poster: each card observes only its own (see `GridPointer`).
@Observable @MainActor
final class LiftBox {
    var lifted = false
}

/// The poster grid's pointer (1.11, spec §9.1): one tracker for the whole grid. The posters are
/// all the same size, so the first few say where they are and the poster under the pointer is
/// worked out from its position; nothing is tracked while the grid scrolls. Right-click opens
/// the poster's menu from here too, so no poster carries a menu of its own.
@MainActor
final class GridPointer {
    /// The grid's items in order, as shown (set each time the grid is drawn).
    var items: [LibraryItem] = []
    weak var scroll: ScrollState?
    let space = UUID()
    /// The first posters' frames, enough to know the columns and rows.
    static let measured = 24
    private var frames: [Int: CGRect] = [:]
    private var boxes: [String: LiftBox] = [:]
    private var current: String?
    /// Opens a poster clicked while none is lifted (just after a scroll, before the pointer
    /// moves): the posters only take clicks while lifted (1.11.2, see `HitTestedWhenLifted`).
    var open: ((LibraryItem) -> Void)?

    /// A poster is lifted under the pointer.
    var isLifted: Bool { current != nil }

    func box(_ id: String) -> LiftBox {
        if let box = boxes[id] { return box }
        let box = LiftBox()
        boxes[id] = box
        return box
    }

    func place(_ index: Int, frame: CGRect) { frames[index] = frame }

    /// The item under a point in the grid's space, if any (not in the gaps between posters).
    func item(at point: CGPoint) -> LibraryItem? {
        guard let first = frames[0], first.width > 0, first.height > 0 else { return nil }
        let columns = max(1, frames.values.filter { abs($0.minY - first.minY) < 1 }.count)
        let pitchX = columns > 1 ? (frames[1].map { $0.minX - first.minX } ?? first.width) : first.width
        let pitchY = frames[columns].map { $0.minY - first.minY } ?? (first.height + 30)
        guard pitchX > 0, pitchY > 0 else { return nil }
        let column = Int(((point.x - first.minX) / pitchX).rounded(.down))
        let row = Int(((point.y - first.minY) / pitchY).rounded(.down))
        guard column >= 0, column < columns, row >= 0 else { return nil }
        let x = point.x - first.minX - CGFloat(column) * pitchX
        let y = point.y - first.minY - CGFloat(row) * pitchY
        guard x <= first.width, y <= first.height else { return nil }
        let index = row * columns + column
        return index < items.count ? items[index] : nil
    }

    func pointer(at point: CGPoint?) {
        if scroll?.isScrolling == true {
            settle()
            return
        }
        let hit = point.flatMap { item(at: $0) }
        guard hit?.id != current else { return }
        settle()
        guard let hit else { return }
        current = hit.id
        box(hit.id).lifted = true
        scroll?.pointed = hit
        scroll?.endHover = { [weak self] in self?.settle() }
    }

    func settle() {
        guard let id = current else { return }
        current = nil
        boxes[id]?.lifted = false
        if scroll?.pointed?.id == id { scroll?.pointed = nil }
    }

    /// Forgets the frames when the grid's layout may have changed (another poster size).
    func reset() {
        frames = [:]
        settle()
    }
}

private struct GridPointerKey: EnvironmentKey {
    static let defaultValue: GridPointer? = nil
}

extension EnvironmentValues {
    var gridPointer: GridPointer? {
        get { self[GridPointerKey.self] }
        set { self[GridPointerKey.self] = newValue }
    }
}

extension View {
    /// The grid's single pointer tracker and its right-click menu (see `GridPointer`).
    func gridPointer(_ pointer: GridPointer, menu: @escaping (LibraryItem) -> NSMenu?) -> some View {
        modifier(GridPointerModifier(pointer: pointer, menu: menu))
    }

    /// A poster of a pointer grid is hit-tested only while it's lifted (1.11.2). AppKit hit-tests
    /// the window on every frame while a page scrolls, and SwiftUI then walked every poster's
    /// click, hover and text areas: half the main thread's work on Alex's Mac. The grid knows the
    /// poster under the pointer from its position, so the others needn't answer.
    func hitTestedWhenLifted(_ box: LiftBox?) -> some View {
        modifier(HitTestedWhenLifted(box: box))
    }

    /// One of the first posters of a pointer grid says where it is (the rest needn't).
    func gridCell(_ index: Int, in pointer: GridPointer?) -> some View {
        modifier(GridCell(index: index, pointer: pointer))
    }
}

private struct GridPointerModifier: ViewModifier {
    @Environment(ScrollState.self) private var scroll: ScrollState?
    let pointer: GridPointer
    let menu: (LibraryItem) -> NSMenu?

    func body(content: Content) -> some View {
        let pointer = pointer
        let scroll = scroll
        content
            .environment(\.gridPointer, pointer)
            .coordinateSpace(.named(pointer.space))
            // The whole grid follows the pointer, gaps and posters that aren't hit-tested included.
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                pointer.scroll = scroll
                switch phase {
                case .active(let point): pointer.pointer(at: point)
                case .ended: pointer.pointer(at: nil)
                }
            }
            .overlay {
                RightClickMenu(menu: { point in pointer.item(at: point).flatMap(menu) },
                               takesClick: { point in !pointer.isLifted && pointer.item(at: point) != nil },
                               click: { point in if let item = pointer.item(at: point) { pointer.open?(item) } })
            }
            .onDisappear { pointer.settle() }
    }
}

/// Observes its poster's own lift only, so lifting one poster redraws nothing else.
private struct HitTestedWhenLifted: ViewModifier {
    let box: LiftBox?

    func body(content: Content) -> some View {
        content.allowsHitTesting(box?.lifted ?? true)
    }
}

private struct GridCell: ViewModifier {
    let index: Int
    let pointer: GridPointer?

    func body(content: Content) -> some View {
        if let pointer, index < GridPointer.measured {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(pointer.space)) } action: { pointer.place(index, frame: $0) }
        } else {
            content
        }
    }
}

// MARK: - Right-click

/// A view over the grid that takes right-clicks (and Control-clicks), and shows the menu for the
/// point clicked; and a click on a poster while none is lifted (it opens it). Every other click
/// goes to the posters below.
private struct RightClickMenu: NSViewRepresentable {
    let menu: (CGPoint) -> NSMenu?
    /// Whether a plain click at the point is this view's (see `GridPointer.open`).
    let takesClick: (CGPoint) -> Bool
    let click: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.menuAt = menu
        view.takesClick = takesClick
        view.click = click
    }

    final class CatcherView: NSView {
        var menuAt: ((CGPoint) -> NSMenu?)?
        var takesClick: ((CGPoint) -> Bool)?
        var click: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }

        private func isMenuClick(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }

        private func isPlainClick(_ event: NSEvent?) -> Bool {
            event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let event = NSApp.currentEvent
            if isMenuClick(event) { return super.hitTest(point) }
            if isPlainClick(event), let superview, takesClick?(convert(point, from: superview)) == true { return super.hitTest(point) }
            return nil
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            menuAt?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            if isPlainClick(event) {
                click?(convert(event.locationInWindow, from: nil))
                return
            }
            guard let menu = menu(for: event) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

/// A menu item that runs a closure.
final class MenuAction: NSObject {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }

    static func item(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.isEnabled = enabled
        return item
    }
}
#endif
