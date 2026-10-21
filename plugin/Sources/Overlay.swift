import AppKit

private let settings = UserDefaults.standard

final class QuotaPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StripView: NSView {
    weak var controller: OverlayController?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var mouseStart = NSPoint.zero
    private var windowStart = NSPoint.zero
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        guard let controller else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = NSColor(calibratedWhite: dark ? 0.73 : 0.42, alpha: 1)
        symbol("line.3.horizontal", at: NSRect(x: 8, y: 11, width: 10, height: 10), color: textColor)
        if let error = controller.currentError {
            drawText(error + " · 点击重试", at: 28, color: textColor)
            return
        }
        guard let snapshot = controller.snapshot else {
            drawText("正在读取 Codex 额度…", at: 28, color: textColor)
            return
        }
        var groups = controller.summary(snapshot, compact: false)
        if contentWidth(groups) > bounds.width {
            groups = controller.summary(snapshot, compact: true)
        }
        var x: CGFloat = 28
        for (index, group) in groups.enumerated() {
            if index > 0 {
                drawText("·", at: x, color: NSColor.tertiaryLabelColor)
                x += 19
            }
            symbol(index == 0 ? "gauge" : "calendar", at: NSRect(x: x, y: 9, width: 14, height: 14), color: textColor)
            x += 21
            drawText(group, at: x, color: textColor)
            x += width(group) + 14
        }
    }

    func preferredWidth(maximum: CGFloat) -> CGFloat {
        if let error = controller?.currentError {
            return min(maximum, ceil(40 + width(error + " · 点击重试")))
        }
        guard let controller, let snapshot = controller.snapshot else {
            return min(maximum, ceil(40 + width("正在读取 Codex 额度…")))
        }
        let full = controller.summary(snapshot, compact: false)
        let groups = contentWidth(full) <= maximum ? full : controller.summary(snapshot, compact: true)
        return min(maximum, ceil(contentWidth(groups)))
    }

    private func contentWidth(_ groups: [String]) -> CGFloat {
        // 左侧拖动区 28、每组图标 21、组间距 33、右侧留白 12。
        28 + groups.map { width($0) + 21 }.reduce(0, +) + CGFloat(max(0, groups.count - 1)) * 33 + 12
    }

    private func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]).width
    }

    private func drawText(_ text: String, at x: CGFloat, color: NSColor) {
        (text as NSString).draw(at: NSPoint(x: x, y: 8), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), .foregroundColor: color
        ])
    }

    private func symbol(_ name: String, at rect: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?.draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        mouseStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = NSPoint(x: NSEvent.mouseLocation.x - mouseStart.x, y: NSEvent.mouseLocation.y - mouseStart.y)
        guard dragged || hypot(delta.x, delta.y) > 3 else { return }
        dragged = true
        controller?.isDragging = true
        controller?.popover.close()
        NSCursor.closedHand.set()
        controller?.move(to: NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.isDragging = false
        if dragged { controller?.savePosition(); NSCursor.openHand.set() }
        else { controller?.toggleDetails() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let controller else { return }
        NSMenu.popUpContextMenu(controller.contextMenu(), with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool { controller?.toggleDetails(); return true }
}

final class OverlayController: NSObject, NSApplicationDelegate {
    let client = CodexClient()
    let panel = QuotaPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 32),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let strip = StripView()
    let popover = NSPopover()
    var snapshot: QuotaSnapshot?
    var currentError: String?
    var isDragging = false
    private var hostFrame: NSRect?
    private var visibilityReason = "starting"
    private var timer: Timer?
    private var signals: [DispatchSourceSignal] = []
    private var lastDiagnostics = Date.distantPast
    private let stateDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodexQuotaBar", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "local.wdk.codex-quota-bar"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        strip.controller = self
        strip.setAccessibilityElement(true)
        strip.setAccessibilityRole(.button)
        panel.contentView = strip
        popover.behavior = .transient
        popover.animates = false
        client.onChange = { [weak self] snapshot, error in
            guard let self else { return }
            if let snapshot { self.snapshot = snapshot }
            self.currentError = error
            self.updateStrip()
            if self.popover.isShown { self.populateDetails() }
            self.writeDiagnostics()
        }
        client.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.track() }
        for code in [SIGTERM, SIGINT] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            signals.append(source)
            source.resume()
        }
        updateStrip()
        track()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        client.stop()
        try? FileManager.default.removeItem(at: stateDirectory.appendingPathComponent("status.json"))
    }

    func summary(_ snapshot: QuotaSnapshot, compact: Bool) -> [String] {
        [("5 小时", snapshot.fiveHour), ("本周", snapshot.weekly)].map { label, window in
            guard let window else { return "\(label) --" }
            let suffix = compact ? "" : " · \(resetText(window, short: true))"
            return "\(label)剩余 \(window.remaining)%\(suffix)"
        }
    }

    private func resetText(_ window: QuotaWindow, short: Bool) -> String {
        guard let date = window.resetDate else { return "重置时间未知" }
        if date <= Date() { return "等待额度更新" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = short ? (Calendar.current.isDateInToday(date) ? "HH:mm" : "MM/dd HH:mm") : "M 月 d 日 HH:mm"
        return formatter.string(from: date) + " 重置"
    }

    private func updateStrip() {
        let accessibility: String
        if let error = currentError { accessibility = error }
        else if let snapshot { accessibility = summary(snapshot, compact: false).joined(separator: "；") }
        else { accessibility = "正在读取 Codex 额度" }
        strip.toolTip = accessibility + "\n拖动调整位置；单击查看详情；右键选择位置或退出"
        strip.setAccessibilityLabel(accessibility)
        strip.needsDisplay = true
    }

    private func track() {
        if let snapshot, currentError == nil, Date().timeIntervalSince(snapshot.fetchedAt) > 180 {
            currentError = "额度数据已过期"
        }
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        let pids = Set(applications.map { $0.processIdentifier })
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        visibilityReason = pids.isEmpty ? "codex-not-running" : "codex-not-frontmost"
        if activePID.map({ pids.contains($0) || $0 == ownPID }) == true {
            visibilityReason = "codex-window-unavailable"
        }
        guard !pids.isEmpty, activePID.map({ pids.contains($0) || $0 == ownPID }) == true,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: { item in
                  guard let pid = item[kCGWindowOwnerPID as String] as? Int32,
                        pids.contains(pid), item[kCGWindowLayer as String] as? Int == 0,
                        let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                        let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                  return rect.width > 320 && rect.height > 200
              }), let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let cgRect = CGRect(dictionaryRepresentation: bounds), let mainScreen = NSScreen.screens.first else {
            hostFrame = nil
            popover.close()
            panel.orderOut(nil)
            recordIfNeeded()
            return
        }
        let host = NSRect(x: cgRect.minX, y: mainScreen.frame.maxY - cgRect.maxY, width: cgRect.width, height: cgRect.height)
        hostFrame = host
        visibilityReason = "visible"
        if !isDragging {
            let maximum = max(280, host.width - 24)
            let size = NSSize(width: strip.preferredWidth(maximum: maximum), height: 32)
            panel.setContentSize(size)
            let defaultX = host.width > 900 ? 0.7 : 0.5
            let x = settings.object(forKey: "positionX") == nil ? defaultX : settings.double(forKey: "positionX")
            let y = settings.double(forKey: "positionY")
            let origin = BarGeometry.origin(in: host, size: size, x: x, y: y)
            move(to: origin)
        }
        panel.orderFrontRegardless()
        updateStrip()
        recordIfNeeded()
    }

    func move(to origin: NSPoint) {
        guard let host = hostFrame else { return }
        let relative = BarGeometry.relative(origin, in: host, size: panel.frame.size)
        var position = BarGeometry.origin(in: host, size: panel.frame.size, x: relative.x, y: relative.y)
        let center = NSPoint(x: position.x + panel.frame.width / 2, y: position.y + panel.frame.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            let frame = screen.visibleFrame
            position.x = min(max(frame.minX, position.x), max(frame.minX, frame.maxX - panel.frame.width))
            position.y = min(max(frame.minY, position.y), max(frame.minY, frame.maxY - panel.frame.height))
        }
        panel.setFrameOrigin(position)
    }

    func savePosition() {
        guard let host = hostFrame else { return }
        let position = BarGeometry.relative(panel.frame.origin, in: host, size: panel.frame.size)
        settings.set(position.x, forKey: "positionX")
        settings.set(position.y, forKey: "positionY")
        writeDiagnostics()
    }

    @objc private func refreshQuota() { client.refresh() }

    @objc private func choosePosition(_ sender: NSMenuItem) {
        let positions: [(Double, Double)] = [(0, 1), (1, 1), (0, 0), (0.5, 0), (1, 0)]
        let point = positions[sender.tag]
        settings.set(point.0, forKey: "positionX")
        settings.set(point.1, forKey: "positionY")
        popover.close()
        track()
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let refresh = menu.addItem(withTitle: "立即刷新额度", action: #selector(refreshQuota), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(.separator())
        for (index, title) in ["左上角", "右上角", "左下角", "底部居中", "右下角"].enumerated() {
            let item = menu.addItem(withTitle: title, action: #selector(choosePosition(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出额度条", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        return menu
    }

    func toggleDetails() {
        if popover.isShown { popover.close(); return }
        if currentError != nil { client.refresh() }
        populateDetails()
        popover.show(relativeTo: strip.bounds, of: strip, preferredEdge: .maxY)
    }

    private func populateDetails() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        func label(_ text: String, font: NSFont = .systemFont(ofSize: 12), color: NSColor = .labelColor) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = font
            label.textColor = color
            label.preferredMaxLayoutWidth = 300
            return label
        }
        stack.addArrangedSubview(label("Codex 剩余额度", font: .systemFont(ofSize: 14, weight: .semibold)))
        if let error = currentError {
            stack.addArrangedSubview(label(error, color: .secondaryLabelColor))
        } else if let snapshot {
            for (title, window) in [("5 小时额度", snapshot.fiveHour), ("每周额度", snapshot.weekly)] {
                stack.addArrangedSubview(label(title + (window.map { "    剩余 \($0.remaining)%" } ?? "    暂未提供"),
                                               font: .systemFont(ofSize: 12, weight: .medium)))
                if let window {
                    let progress = NSProgressIndicator()
                    progress.isIndeterminate = false
                    progress.minValue = 0
                    progress.maxValue = 100
                    progress.doubleValue = Double(window.remaining)
                    progress.style = .bar
                    progress.widthAnchor.constraint(equalToConstant: 300).isActive = true
                    progress.setAccessibilityLabel(title + "剩余百分比")
                    stack.addArrangedSubview(progress)
                    stack.addArrangedSubview(label(resetText(window, short: false), color: .secondaryLabelColor))
                }
            }
        } else {
            stack.addArrangedSubview(label("正在读取…", color: .secondaryLabelColor))
        }
        if let snapshot {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            stack.addArrangedSubview(label("上次更新 \(formatter.string(from: snapshot.fetchedAt)) · 每分钟刷新", font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        }
        let button = NSButton(title: "立即刷新", target: self, action: #selector(refreshQuota))
        button.bezelStyle = .rounded
        stack.addArrangedSubview(button)
        stack.addArrangedSubview(label("拖动横条调整位置，右键切换预设位置。", font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        let view = NSView()
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalToConstant: 300)
        ])
        let vc = NSViewController()
        vc.view = view
        let fitted = stack.fittingSize
        vc.preferredContentSize = NSSize(width: 336, height: fitted.height + 36)
        popover.contentViewController = vc
    }

    private func recordIfNeeded() {
        if Date().timeIntervalSince(lastDiagnostics) > 3 { writeDiagnostics() }
    }

    private func writeDiagnostics() {
        lastDiagnostics = Date()
        var state: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "targetDetected": hostFrame != nil, "visible": panel.isVisible, "visibilityReason": visibilityReason,
            "error": currentError ?? NSNull(), "frame": NSStringFromRect(panel.frame),
            "positionX": settings.object(forKey: "positionX") ?? NSNull(),
            "positionY": settings.object(forKey: "positionY") ?? NSNull()
        ]
        if let snapshot, let data = try? JSONEncoder().encode(snapshot),
           let object = try? JSONSerialization.jsonObject(with: data) { state["quota"] = object }
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: stateDirectory.appendingPathComponent("status.json"), options: .atomic)
        }
    }
}
