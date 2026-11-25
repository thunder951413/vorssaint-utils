// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Cocoa
import Darwin

/// Dynamically resolved private CGS/Carbon/AX helpers used by MenuBarHider.
/// Resolved via dlopen/dlsym so future macOS changes degrade gracefully.
enum MenuBarHiderPrivateBridge {
    typealias ConnectionID = Int32
    typealias SpaceID = UInt

    enum SpaceType: UInt32 {
        case user = 0
        case system = 2
        case fullscreen = 4
    }

    private typealias MainConnectionFn = @convention(c) () -> ConnectionID
    private typealias SetConnectionPropertyFn = @convention(c) (ConnectionID, ConnectionID, CFString, CFTypeRef) -> CGError
    private typealias GetActiveSpaceFn = @convention(c) (ConnectionID) -> SpaceID
    private typealias SpaceGetTypeFn = @convention(c) (ConnectionID, SpaceID) -> UInt32
    private typealias IsAppUnresponsiveFn = @convention(c) (ConnectionID, UnsafeMutablePointer<ProcessSerialNumber>) -> Bool
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
            ?? dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    }()

    private static func resolve<T>(_ name: String, in handle: UnsafeMutableRawPointer? = skyLightHandle, as type: T.Type) -> T? {
        if let handle, let sym = dlsym(handle, name) {
            return unsafeBitCast(sym, to: type)
        }
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            return unsafeBitCast(sym, to: type)
        }
        return nil
    }

    private static let mainConnectionFn = resolve("CGSMainConnectionID", as: MainConnectionFn.self)
    private static let setConnectionPropertyFn = resolve("CGSSetConnectionProperty", as: SetConnectionPropertyFn.self)
    private static let getActiveSpaceFn = resolve("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let spaceGetTypeFn = resolve("CGSSpaceGetType", as: SpaceGetTypeFn.self)
    private static let isAppUnresponsiveFn = resolve("CGSEventIsAppUnresponsive", as: IsAppUnresponsiveFn.self)
    private static let getProcessForPIDFn = resolve("GetProcessForPID", in: nil, as: GetProcessForPIDFn.self)
    private static let axUIElementGetWindowFn = resolve("_AXUIElementGetWindow", in: nil, as: AXUIElementGetWindowFn.self)

    static var activeSpaceID: SpaceID {
        guard let mainConn = mainConnectionFn, let activeSpace = getActiveSpaceFn else { return 0 }
        return activeSpace(mainConn())
    }

    static var isActiveSpaceFullscreen: Bool {
        guard let mainConn = mainConnectionFn,
              let activeSpace = getActiveSpaceFn,
              let spaceType = spaceGetTypeFn
        else { return false }
        let cid = mainConn()
        let sid = activeSpace(cid)
        return SpaceType(rawValue: spaceType(cid, sid)) == .fullscreen
    }

    static func setCursorInBackground(_ enabled: Bool) {
        guard let mainConn = mainConnectionFn, let setProp = setConnectionPropertyFn else { return }
        let cid = mainConn()
        _ = setProp(cid, cid, "SetsCursorInBackground" as CFString, enabled as CFBoolean)
    }

    static func isApplicationResponsive(pid: pid_t) -> Bool {
        guard let mainConn = mainConnectionFn,
              let isUnresponsive = isAppUnresponsiveFn,
              let getPSN = getProcessForPIDFn
        else { return true }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return true }
        return !isUnresponsive(mainConn(), &psn)
    }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let fn = axUIElementGetWindowFn else { return nil }
        var wid: CGWindowID = 0
        guard fn(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }
}

/// Lightweight window descriptor from CoreGraphics window lists.
struct MenuBarHiderWindowInfo: Hashable {
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let layer: Int
    let alpha: Double
    let ownerPID: pid_t
    let ownerName: String?
    let isOnScreen: Bool

    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    var isWindowServerWindow: Bool {
        ownerName == "Window Server"
    }

    init(
        windowID: CGWindowID,
        frame: CGRect,
        title: String?,
        layer: Int,
        alpha: Double,
        ownerPID: pid_t,
        ownerName: String?,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.frame = frame
        self.title = title
        self.layer = layer
        self.alpha = alpha
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.isOnScreen = isOnScreen
    }

    private init?(dictionary: CFDictionary) {
        guard
            let info = dictionary as? [CFString: CFTypeRef],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let boundsDict = info[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: boundsDict),
            let layer = info[kCGWindowLayer] as? Int,
            let alpha = info[kCGWindowAlpha] as? Double,
            let ownerPID = info[kCGWindowOwnerPID] as? pid_t
        else {
            return nil
        }
        self.windowID = windowID
        self.frame = frame
        self.title = info[kCGWindowName] as? String
        self.layer = layer
        self.alpha = alpha
        self.ownerPID = ownerPID
        self.ownerName = info[kCGWindowOwnerName] as? String
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }

    static func getOnScreenWindows(excludeDesktopWindows: Bool = false) -> [MenuBarHiderWindowInfo] {
        var option: CGWindowListOption = [.optionOnScreenOnly]
        if excludeDesktopWindows {
            option.insert(.excludeDesktopElements)
        }
        guard let list = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [CFDictionary] else {
            return []
        }
        return list.compactMap { MenuBarHiderWindowInfo(dictionary: $0) }
    }

    static func getMenuBarWindow(for display: CGDirectDisplayID) -> MenuBarHiderWindowInfo? {
        let displayBounds = CGDisplayBounds(display)
        return getOnScreenWindows(excludeDesktopWindows: true).first { window in
            window.isWindowServerWindow
                && window.isOnScreen
                && window.layer == Int(kCGMainMenuWindowLevel)
                && (window.title == "Menubar" || (abs(window.frame.width - displayBounds.width) <= 2 && window.frame.height <= 80))
                && displayBounds.intersects(window.frame)
        }
    }

    static func == (lhs: MenuBarHiderWindowInfo, rhs: MenuBarHiderWindowInfo) -> Bool {
        lhs.windowID == rhs.windowID
            && NSStringFromRect(lhs.frame) == NSStringFromRect(rhs.frame)
            && lhs.title == rhs.title
            && lhs.layer == rhs.layer
            && lhs.alpha == rhs.alpha
            && lhs.ownerPID == rhs.ownerPID
            && lhs.ownerName == rhs.ownerName
            && lhs.isOnScreen == rhs.isOnScreen
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(NSStringFromRect(frame))
        hasher.combine(title)
        hasher.combine(layer)
        hasher.combine(alpha)
        hasher.combine(ownerPID)
        hasher.combine(ownerName)
        hasher.combine(isOnScreen)
    }
}

/// Mouse cursor helpers for synthetic click delivery without visible pointer jump.
enum MenuBarHiderCursor {
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    static func hide() {
        _ = CGDisplayHideCursor(CGMainDisplayID())
    }

    static func show() {
        _ = CGDisplayShowCursor(CGMainDisplayID())
    }

    static func warp(to point: CGPoint) {
        _ = CGWarpMouseCursorPosition(point)
    }
}

/// Small screen geometry helpers scoped to MenuBarHider to avoid name clashes.
enum MenuBarHiderScreenGeometry {
    static var screenWithMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
            return screen
        }
        return NSScreen.screens.first { screen in
            let frame = screen.frame
            return location.x >= frame.minX && location.x < frame.maxX && location.y == frame.maxY
        }
    }

    static func menuBarMinY(for screen: NSScreen) -> CGFloat {
        if screen.visibleFrame.maxY < screen.frame.maxY {
            return screen.visibleFrame.maxY
        }
        return screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
    }

    static func menuBarContains(_ point: CGPoint, on screen: NSScreen) -> Bool {
        point.x >= screen.frame.minX && point.x < screen.frame.maxX
            && point.y >= menuBarMinY(for: screen) && point.y <= screen.frame.maxY
    }

    static func frameOfNotch(for screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        return CGRect(
            x: left.maxX,
            y: screen.frame.maxY - screen.safeAreaInsets.top,
            width: right.minX - left.maxX,
            height: screen.safeAreaInsets.top
        )
    }

    static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        if screen.visibleFrame.maxY < screen.frame.maxY {
            return screen.frame.maxY - screen.visibleFrame.maxY
        }
        if let menuBarWindow = MenuBarHiderWindowInfo.getMenuBarWindow(for: screen.displayID) {
            return menuBarWindow.frame.height
        }
        return max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
    }
}

/// Combined local + global NSEvent monitor with balanced lifecycle management.
final class MenuBarHiderUniversalMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    private var localToken: Any?
    private var globalToken: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        if localToken == nil {
            localToken = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        }
        if globalToken == nil {
            globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                _ = self?.handler(event)
            }
        }
    }

    func stop() {
        if let localToken {
            NSEvent.removeMonitor(localToken)
            self.localToken = nil
        }
        if let globalToken {
            NSEvent.removeMonitor(globalToken)
            self.globalToken = nil
        }
    }
}
