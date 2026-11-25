// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import Combine
import SwiftUI

/// Lightweight floating bar panel displaying hidden menu bar apps below the menu bar.
@MainActor
final class MenuBarHiderPanel: NSPanel {
    private static let escapeKeyCode: UInt16 = 53

    private weak var service: MenuBarHiderService?

    private(set) var currentSection: MenuBarHiderSection?
    private(set) var presentationGeneration = 0
    private weak var targetScreen: NSScreen?
    private var resolvedAnchor: (location: MenuBarHiderBarLocation, mouseX: CGFloat?)?

    private var cancellables = Set<AnyCancellable>()
    private var escapeMonitorToken: Any?

    override var canBecomeKey: Bool { true }

    init(service: MenuBarHiderService) {
        self.service = service
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        title = "Menu Bar Hider"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        allowsToolTipsWhenApplicationIsInactive = true
        isFloatingPanel = true
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .mainMenu + 1
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        configureObservers()
    }

    private func configureObservers() {
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.close()
        }
        .store(in: &cancellables)

        publisher(for: \.frame)
            .map(\.size)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let screen = self.targetScreen ?? self.screen else { return }
                self.updateOrigin(for: screen)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: self)
            .delay(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible, !self.isKeyWindow else { return }
                self.close()
            }
            .store(in: &cancellables)
    }

    private func updateOrigin(for screen: NSScreen) {
        guard let service else { return }
        let menuBarHeight = MenuBarHiderScreenGeometry.menuBarHeight(for: screen)
        let originY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

        func clampX(_ proposed: CGFloat) -> CGFloat {
            let lower = screen.frame.minX
            let upper = screen.frame.maxX - frame.width
            guard lower <= upper else { return screen.frame.maxX - frame.width }
            return min(max(proposed, lower), upper)
        }

        func computeOrigin(for location: MenuBarHiderBarLocation) -> CGPoint {
            switch location {
            case .dynamic:
                if let resolved = resolvedAnchor?.location, resolved != .dynamic {
                    return computeOrigin(for: resolved)
                }
                if service.isMouseInsideEmptyMenuBarSpace {
                    return computeOrigin(for: .mousePointer)
                }
                return computeOrigin(for: .triggerIcon)
            case .mousePointer:
                guard let locationX = resolvedAnchor?.mouseX ?? MenuBarHiderCursor.locationAppKit?.x else {
                    return CGPoint(x: screen.frame.maxX - frame.width, y: originY)
                }
                return CGPoint(x: clampX(locationX - frame.width / 2), y: originY)
            case .triggerIcon:
                if let anchorX = service.triggerIconAnchorX(on: screen), frame.width <= screen.frame.width {
                    return CGPoint(x: clampX(anchorX - frame.width / 2), y: originY)
                }
                return computeOrigin(for: .mousePointer)
            }
        }

        setFrameOrigin(computeOrigin(for: service.barLocation))
    }

    func show(section: MenuBarHiderSection, on screen: NSScreen, menuBarClickX: CGFloat? = nil) async {
        guard let service else { return }
        presentationGeneration += 1
        targetScreen = screen

        let configuredLocation = service.barLocation
        let effectiveLocation: MenuBarHiderBarLocation = if configuredLocation == .dynamic {
            (menuBarClickX != nil || service.isMouseInsideEmptyMenuBarSpace) ? .mousePointer : .triggerIcon
        } else {
            configuredLocation
        }
        resolvedAnchor = (effectiveLocation, menuBarClickX ?? MenuBarHiderCursor.locationAppKit?.x)
        currentSection = section

        let hostingView = MenuBarHiderHostingView(service: service, screen: screen, section: section) { [weak self] in
            self?.close()
        }
        contentView = hostingView
        updateOrigin(for: screen)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = reduceMotion ? 1 : 0
        makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.12
            animator().alphaValue = 1
            NSAnimationContext.endGrouping()
        }

        startEscapeMonitor()
        DispatchQueue.main.async { [weak self, weak hostingView] in
            guard self?.isKeyWindow == true else { return }
            hostingView?.focusFirstItem()
        }

        Task { @MainActor [weak service] in
            try? await Task.sleep(for: .milliseconds(250))
            await service?.cacheItemsIfNeeded()
        }
    }

    override func close() {
        presentationGeneration += 1
        stopEscapeMonitor()
        super.close()
        contentView = nil
        currentSection = nil
        targetScreen = nil
        resolvedAnchor = nil
        service?.noteBarClosed()
    }

    private func startEscapeMonitor() {
        stopEscapeMonitor()
        escapeMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isKeyWindow, event.keyCode == Self.escapeKeyCode else {
                return event
            }
            self.close()
            return nil
        }
    }

    private func stopEscapeMonitor() {
        if let escapeMonitorToken {
            NSEvent.removeMonitor(escapeMonitorToken)
            self.escapeMonitorToken = nil
        }
    }
}

// MARK: - Hosting View

private final class MenuBarHiderHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(
        service: MenuBarHiderService,
        screen: NSScreen,
        section: MenuBarHiderSection,
        closePanel: @escaping () -> Void
    ) {
        super.init(
            rootView: AnyView(
                MenuBarHiderBarContentView(
                    service: service,
                    screen: screen,
                    section: section,
                    closePanel: closePanel
                )
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func focusFirstItem() {
        func focusableButtons(in view: NSView) -> [NSView] {
            view.subviews.flatMap { subview in
                let current = subview.acceptsFirstResponder
                    && subview.isAccessibilityElement()
                    && subview.accessibilityRole() == .button ? [subview] : []
                return current + focusableButtons(in: subview)
            }
        }
        guard let first = focusableButtons(in: self).min(by: {
            $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
        }) else { return }
        window?.makeFirstResponder(first)
        first.scrollToVisible(first.bounds)
    }
}

// MARK: - Bar Surface

private struct MenuBarHiderVisualEffectView: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

private struct MenuBarHiderBarSurface: View {
    let style: MenuBarHiderBarStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let cornerRadius: CGFloat = 10

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var fillColor: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.17, blue: 0.19)
            : Color(red: 0.96, green: 0.97, blue: 0.98)
    }

    var body: some View {
        ZStack {
            if style == .frosted && !reduceTransparency {
                MenuBarHiderVisualEffectView(cornerRadius: cornerRadius)
                fillColor.opacity(0.84)
            } else {
                fillColor
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.16),
                lineWidth: contrast == .increased ? 2 : 1
            )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 6, x: 0, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bar Content View

private struct MenuBarHiderBarContentView: View {
    @ObservedObject var service: MenuBarHiderService
    @ObservedObject private var l10n = L10n.shared
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var loadingTimedOut = false

    let screen: NSScreen
    let section: MenuBarHiderSection
    let closePanel: () -> Void

    private var strings: MenuBarHiderFeatureStrings {
        FeatureStrings.menuBarHider(l10n.language)
    }

    private var items: [MenuBarHiderItem] {
        service.managedItems(in: section)
    }

    private var availableWidth: CGFloat {
        max(160, screen.frame.width - 32)
    }

    private var maxScrollWidth: CGFloat {
        max(64, availableWidth - 16 - (service.barPadding + 2) * 2)
    }

    private var itemsRowWidth: CGFloat {
        let count = items.count
        guard count > 0 else { return 0 }
        return CGFloat(count) * (service.iconSize + 4) + CGFloat(count - 1) * service.itemSpacing
    }

    var body: some View {
        content
            .frame(minHeight: service.iconSize + 4)
            .padding(.horizontal, service.barPadding + 2)
            .padding(.vertical, service.barPadding)
            .foregroundStyle(.primary)
            .background { MenuBarHiderBarSurface(style: service.barStyle) }
            .contentShape(Rectangle())
            .contextMenu {
                Button(strings.menuManageIcons) {
                    closePanel()
                    service.onOpenSettings?()
                }
                Divider()
                Button(service.isHidingPaused ? strings.menuResumeHiding : strings.menuPauseHiding) {
                    closePanel()
                    service.toggleHidingPaused()
                }
                Divider()
                Button(strings.menuCloseBar, action: closePanel)
            }
            .padding(8)
            .frame(maxWidth: availableWidth)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if service.isMenuBarHiddenBySystemUserDefaults {
            Text(strings.barAutoHiddenNotice)
                .font(.callout)
                .padding(.horizontal, 12)
        } else if items.isEmpty, !service.hasCompletedInitialScan, !loadingTimedOut {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 12)
                .accessibilityLabel(strings.scanningItems)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    loadingTimedOut = true
                }
        } else if items.isEmpty {
            Text(String(format: strings.emptyBarFormat, strings.sectionTitle(section)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: service.itemSpacing) {
                    ForEach(items) { item in
                        MenuBarHiderBarItemView(
                            service: service,
                            item: item,
                            strings: strings,
                            closePanel: closePanel
                        )
                    }
                }
            }
            .frame(width: min(itemsRowWidth, maxScrollWidth))
            .defaultScrollAnchor(.trailing)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }
}

// MARK: - Bar Item View

private struct MenuBarHiderBarItemView: View {
    @ObservedObject var service: MenuBarHiderService
    let item: MenuBarHiderItem
    let strings: MenuBarHiderFeatureStrings
    let closePanel: () -> Void

    @State private var isHovered = false

    private var iconSide: CGFloat { service.iconSize }
    private var hitTarget: CGFloat { iconSide + 4 }

    private func trigger(_ button: CGMouseButton) {
        closePanel()
        Task { @MainActor [weak service] in
            await Task.yield()
            service?.activateHiddenItem(item, mouseButton: button)
        }
    }

    var body: some View {
        Group {
            if let icon = item.owningApplication?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
            } else {
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: iconSide)
            }
        }
        .frame(
            width: item.owningApplication?.icon != nil ? hitTarget : nil,
            height: hitTarget
        )
        .contentShape(Rectangle())
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.12))
                    .padding(2)
            }
        }
        .accessibilityHidden(true)
        .overlay {
            MenuBarHiderBarItemClickView(
                item: item,
                tooltip: "\(item.displayName)\n\(strings.itemTooltipHint)",
                accessibilityHelpText: strings.itemAccessibilityHelp,
                leftClickAction: { trigger(.left) },
                rightClickAction: { trigger(.right) }
            )
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Native Click / Keyboard Overlay

private struct MenuBarHiderBarItemClickView: NSViewRepresentable {
    private final class Represented: NSView {
        var item: MenuBarHiderItem
        var accessibilityHelpText: String
        var leftClickAction: () -> Void
        var rightClickAction: () -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now
        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        init(
            item: MenuBarHiderItem,
            tooltip: String,
            accessibilityHelpText: String,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void
        ) {
            self.item = item
            self.accessibilityHelpText = accessibilityHelpText
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            super.init(frame: .zero)
            self.toolTip = tooltip
            self.focusRingType = .default
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }
        override var focusRingMaskBounds: NSRect { bounds }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { setKeyboardFocusRingNeedsDisplay(bounds) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { setKeyboardFocusRingNeedsDisplay(bounds) }
            return resigned
        }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            // Suppress parent SwiftUI contextMenu on icon right-click so right-click forwards to the real menu bar app.
            nil
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            window?.makeFirstResponder(self)
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                  hypot(lastLeftMouseDownLocation.x - NSEvent.mouseLocation.x,
                        lastLeftMouseDownLocation.y - NSEvent.mouseLocation.y) < 5
            else { return }
            leftClickAction()
        }

        override func rightMouseDown(with event: NSEvent) {
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseUp(with event: NSEvent) {
            guard Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                  hypot(lastRightMouseDownLocation.x - NSEvent.mouseLocation.x,
                        lastRightMouseDownLocation.y - NSEvent.mouseLocation.y) < 5
            else { return }
            rightClickAction()
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 49: // Return / Space
                leftClickAction()
            case 123: // Left arrow
                moveKeyboardFocus(by: -1)
            case 124: // Right arrow
                moveKeyboardFocus(by: 1)
            default:
                super.keyDown(with: event)
            }
        }

        private func moveKeyboardFocus(by offset: Int) {
            guard let root = window?.contentView else { return }
            func representedViews(in view: NSView) -> [Represented] {
                view.subviews.flatMap { subview in
                    (subview as? Represented).map { [$0] } ?? representedViews(in: subview)
                }
            }
            let views = representedViews(in: root).sorted {
                $0.convert($0.bounds, to: nil).midX < $1.convert($1.bounds, to: nil).midX
            }
            guard let index = views.firstIndex(where: { $0 === self }), !views.isEmpty else { return }
            let next = views[(index + offset + views.count) % views.count]
            window?.makeFirstResponder(next)
            next.scrollToVisible(next.bounds)
        }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { item.displayName }
        override func accessibilityHelp() -> String? { accessibilityHelpText }
        override func accessibilityPerformPress() -> Bool {
            leftClickAction()
            return true
        }
    }

    let item: MenuBarHiderItem
    let tooltip: String
    let accessibilityHelpText: String
    let leftClickAction: () -> Void
    let rightClickAction: () -> Void

    func makeNSView(context: Context) -> NSView {
        Represented(
            item: item,
            tooltip: tooltip,
            accessibilityHelpText: accessibilityHelpText,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? Represented else { return }
        view.item = item
        view.toolTip = tooltip
        view.accessibilityHelpText = accessibilityHelpText
        view.leftClickAction = leftClickAction
        view.rightClickAction = rightClickAction
    }
}
