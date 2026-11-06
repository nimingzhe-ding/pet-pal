import Cocoa
import SwiftUI
import Combine

// MARK: - 桌面宠物主程序
//
// 收起态：一只小鲸鱼娘浮在桌面，可拖动、会走动、点一下展开。
// 展开态：鲸鱼娘下方浮出会话进度面板，右上角 × 或再点一次鲸鱼收回。

// MARK: 宠物状态（由 pet-hook.py 写入）

struct PetState: Codable {
    var phase: String = "idle"
    var level: Int = 1
    var xp: Int = 0
    var xpNeed: Int = 65
    var bond: Int = 0
    var turns: Int = 0
    var tools: Int = 0
    var outputTokens: Int = 0
    var runningTool: String?
    var turnStartedAt: Double = 0
    var lastTurnMs: Double = 0
    var updatedAt: Double = 0
}

final class PetModel: ObservableObject {
    @Published var pet = PetState()
    @Published var isExpanded = false
    @Published var sessions: [SessionRow] = []
    @Published var isBlinking = false
    /// 完成提示：显示在鲸鱼娘头顶
    @Published var notice: String? = nil
    /// 直接引用宠物窗口，拖动时不必每帧遍历窗口列表
    weak var window: NSWindow?
    /// 会话行的全局矩形（SwiftUI global 坐标，原点左上）
    var rowFrames: [RowFrame] = []
    @Published var bob: CGFloat = 0
    @Published var facing: CGFloat = 1

    private var pollTimer: Timer?
    private var walkTimer: Timer?
    private var walkFrameTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/pet-state.json")

    private var lastUpdated = 0.0
    /// 上一次各会话的状态，用于检测「完成」的瞬间
    private var previousStatus: [String: String] = [:]

    /// 完成提示回调
    var onSessionFinished: ((SessionInfo) -> Void)?

    func start() {
        loadPet()
        refreshSessions()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.loadPet()
        }
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.refreshSessions()
        }
        Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.isBlinking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { self.isBlinking = false }
        }
        startBobbing()
    }

    private func loadPet() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(PetState.self, from: data)
        else { return }
        guard decoded.updatedAt != lastUpdated else { return }
        lastUpdated = decoded.updatedAt
        DispatchQueue.main.async {
            self.pet = decoded
            self.startBobbing()
        }
    }

    /// 展示一条完成提示（3 秒后自动消失）
    func showNotice(_ text: String) {
        DispatchQueue.main.async {
            self.notice = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                if self?.notice == text { self?.notice = nil }
            }
        }
    }

    private var hasBaseline = false

    func refreshSessions() {
        let list = SessionReader.readAll()
        DispatchQueue.main.async {
            // 检测刚完成的会话：上一次 busy，这一次不再 busy
            for item in list {
                let was = self.previousStatus[item.id]
                if self.hasBaseline, was == "busy", item.status != "busy" {
                    self.onSessionFinished?(item)
                }
                self.previousStatus[item.id] = item.status
            }
            if !self.hasBaseline {
            }
            self.hasBaseline = true

            self.sessions = list.map {
                SessionRow(
                    id: $0.id, pid: $0.pid, name: $0.name, cwd: $0.cwd, status: $0.status,
                    lastPrompt: $0.lastPrompt, updatedAt: $0.updatedAt, isDone: $0.isDone
                )
            }
        }
    }

    private func startBobbing() {
        bob = 0
        let speed = pet.phase == "working" ? 0.45 : 1.4
        let amount: CGFloat = pet.phase == "working" ? -4 : -2.2
        withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
            bob = amount
        }
    }

    var mood: WhaleMood {
        var m = WhaleMood()
        m.isBlinking = isBlinking
        m.bob = bob
        switch pet.phase {
        case "thinking": m.eye = .open
        case "working":  m.eye = .sparkle
        case "happy":    m.eye = .happy
        case "tired":    m.eye = .sleepy
        case "error":    m.eye = .dizzy
        default:         m.eye = .open
        }
        return m
    }
}

// MARK: 收起态的鲸鱼

struct PetCharacter: View {
    @ObservedObject var model: PetModel
    let onTap: () -> Void

    // 拖拽状态放在 class 里，避免 @State 每帧失效触发重绘
    private final class DragState {
        static let shared = DragState()
        var start: NSPoint?
        var windowStart: NSPoint?
        var didMove = false
    }

    var body: some View {
        WhaleGirl(mood: model.mood)
            .overlay(alignment: .topTrailing) {
                StatusBadge(model: model)
                    .offset(x: -2, y: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let st = DragState.shared
                        guard let win = model.window else { return }
                        if st.start == nil {
                            st.start = value.startLocation
                            st.windowStart = win.frame.origin
                            st.didMove = false
                        }
                        guard let s = st.start, let ws = st.windowStart else { return }
                        let dx = value.location.x - s.x
                        let dy = value.location.y - s.y
                        if abs(dx) > 4 || abs(dy) > 4 { st.didMove = true }
                        // 直接改窗口位置，不触发布局
                        win.setFrameOrigin(NSPoint(x: ws.x + dx, y: ws.y - dy))
                    }
                    .onEnded { _ in
                        let st = DragState.shared
                        // 位移小于 4pt 就算点击
                        let wasClick = !st.didMove
                        st.start = nil
                        st.windowStart = nil
                        st.didMove = false
                        if wasClick { onTap() }
                    }
            )
    }
}

// MARK: 状态徽章（收起时也能看到全局进度）

struct StatusBadge: View {
    @ObservedObject var model: PetModel

    private var busy: Int { model.sessions.filter { $0.status == "busy" }.count }
    private var doneToday: Int { model.sessions.filter { $0.isDone }.count }

    var body: some View {
        HStack(spacing: 3) {
            if busy > 0 {
                Circle()
                    .fill(Color(red: 0.98, green: 0.62, blue: 0.28))
                    .frame(width: 6, height: 6)
                Text("\(busy)")
                    .font(.custom("PingFang SC Semibold", size: 10))
                    .foregroundColor(.white)
            } else if doneToday > 0 {
                Text("✓")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, busy > 0 ? 5 : 3)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(
                busy > 0
                    ? Color(red: 0.98, green: 0.62, blue: 0.28)
                    : Color(red: 0.30, green: 0.72, blue: 0.45)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        )
        .opacity((busy > 0 || doneToday > 0) ? 1 : 0)
    }
}

// MARK: 完成提示气泡

struct NoticeBubble: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text("✅").font(.system(size: 10))
            Text(text)
                .font(.custom("PingFang SC Medium", size: 11))
                .foregroundColor(Color(red: 0.16, green: 0.30, blue: 0.20))
                .lineLimit(2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.88, green: 0.97, blue: 0.90))
                .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(red: 0.45, green: 0.80, blue: 0.55).opacity(0.7), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 200, alignment: .leading)
    }
}

// MARK: 展开态的整块

struct PetWithPanel: View {
    @ObservedObject var model: PetModel
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let notice = model.notice {
                NoticeBubble(text: notice)
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            PetCharacter(model: model, onTap: onToggle)
                .frame(width: 150, height: 118)

            if model.isExpanded {
                SessionPanel(
                    sessions: model.sessions,
                    onClose: onToggle,
                    onOpen: { row in SessionJump.focus(pid: row.pid) },
                    onFrames: { frames in model.rowFrames = frames }
                )
                    .transition(.opacity)
            }
        }
        .frame(width: model.isExpanded ? 268 : 156,
               height: model.isExpanded ? 492 : (model.notice != nil ? 172 : 124),
               alignment: .topLeading)
        .coordinateSpace(name: "winroot")
    }
}

// MARK: - 可点击的 HostingView

final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    /// 由 AppDelegate 注入：视图坐标 -> 命中回调
    var onHit: ((NSPoint) -> Bool)? = nil
    /// 鲸鱼娘本体被点击（非拖动、非会话行）
    var onBodyTap: (() -> Void)? = nil
    /// 右键时提供菜单
    var menuProvider: (() -> NSMenu)? = nil

    private var dragOrigin: NSPoint?
    private var mouseDownAt: NSPoint?

    /// 屏幕坐标 → 窗口内 AppKit 坐标（原点左下）
    private func windowLocalPoint(from event: NSEvent) -> NSPoint {
        guard let win = window else { return .zero }
        let screenPt = NSEvent.mouseLocation          // 屏幕坐标，原点左下
        let winOrigin = win.frame.origin
        return NSPoint(x: screenPt.x - winOrigin.x,
                       y: screenPt.y - winOrigin.y)
    }

    override func mouseDown(with event: NSEvent) {
        // 用屏幕坐标自己算，不用 convert —— 浮动窗口上它不可靠
        let local = windowLocalPoint(from: event)
        if onHit?(local) == true { return }

        mouseDownAt = NSEvent.mouseLocation
        dragOrigin = window?.frame.origin
        AppDelegate.shared?.isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let ws = dragOrigin, let down = mouseDownAt, let win = window else { return }
        let now = NSEvent.mouseLocation
        // 拖动中不钳制：屏幕之间存在缝隙（主屏顶 1084、副屏底 1117），
        // 中途钳制会把窗口卡在边界，根本过不去。松手时再修。
        let origin = NSPoint(x: ws.x + (now.x - down.x),
                             y: ws.y + (now.y - down.y))
        win.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        AppDelegate.shared?.isDragging = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let win = self?.window, let delegate = AppDelegate.shared else { return }
            let fixed = delegate.clampToAnyScreen(win.frame.origin, size: win.frame.size)
            if fixed != win.frame.origin { win.setFrameOrigin(fixed) }
        }

        if let down = mouseDownAt, let ws = dragOrigin, let win = window {
            let now = NSEvent.mouseLocation
            let moved = hypot(now.x - down.x, now.y - down.y)
            if moved < 4 && win.frame.origin == ws {
                onBodyTap?()
            }
        }
        dragOrigin = nil
        mouseDownAt = nil
    }

    /// 右键菜单：HostingView 会吞掉事件，必须在它自己身上弹
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 窗口

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 由 AppDelegate 注入：点在会话行上时返回该行
    var hitTest: ((NSPoint) -> Int?)? = nil
    var onRowClick: ((Int) -> Void)? = nil
    var onBodyClick: (() -> Void)? = nil


}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    let model = PetModel()

    private let collapsedSize = NSSize(width: 156, height: 124)
    private let expandedSize = NSSize(width: 276, height: 500)
    /// 有提示气泡时的高度（气泡 + 鲸鱼）
    private let noticeSize = NSSize(width: 156, height: 172)

    /// 拖动中：看门狗暂停，否则会把窗口每帧拉回屏幕内，跨不了屏
    var isDragging = false
    private var walkTimer: Timer?
    private var walkFrameTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isWalking = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onSessionFinished = { [weak self] info in
            guard let self else { return }
            let short = info.name.isEmpty ? "会话" : info.name
            self.model.showNotice("「\(short)」完成了")
            self.playDoneSound()
        }

        buildWindow()
        model.start()

        // 提示气泡出现/消失时，窗口随之变高/变矮（锚点保持底部）
        model.$notice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.applySize(hasNotice: value != nil)
            }
            .store(in: &cancellables)
        // 默认静止。右键菜单「开始走动」可开启。
        if ProcessInfo.processInfo.environment["PET_WALK"] == "1" {
            isWalking = true
            startWalking()
        }
        if ProcessInfo.processInfo.environment["PET_NO_WD"] != "1" {
            startScreenWatchdog()
        }
    }

    /// 窗口允许停靠的区域：所有屏幕可见区的并集。
    /// 跨屏拖动是允许的，但不能掉进屏幕之间的缝隙或完全跑到外面。
    func clampToAnyScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let screens = NSScreen.screens.map { $0.visibleFrame }
        guard !screens.isEmpty else { return origin }

        // 已经完整落在某块屏内 → 不动
        for s in screens {
            if origin.x >= s.minX, origin.x + size.width <= s.maxX,
               origin.y >= s.minY, origin.y + size.height <= s.maxY {
                return origin
            }
        }

        // 否则吸附到「最近」的那块屏
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        var best = screens[0]
        var bestDist = CGFloat.greatestFiniteMagnitude
        for s in screens {
            let dx = max(s.minX - center.x, 0, center.x - s.maxX)
            let dy = max(s.minY - center.y, 0, center.y - s.maxY)
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = s }
        }

        return NSPoint(
            x: max(best.minX, min(origin.x, best.maxX - size.width)),
            y: max(best.minY, min(origin.y, best.maxY - size.height))
        )
    }

    /// 看门狗：窗口掉出所有屏幕时拉回最近的一块
    private func startScreenWatchdog() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let win = self.window, !self.isDragging else { return }
            let fixed = self.clampToAnyScreen(win.frame.origin, size: win.frame.size)
            if fixed != win.frame.origin { win.setFrameOrigin(fixed) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func buildWindow() {
        // 选屏幕：优先有菜单栏的主屏
        let screen = (NSScreen.screens.first { $0.frame.origin == .zero }
                      ?? NSScreen.main
                      ?? NSScreen.screens.first)?.visibleFrame
                      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let origin = NSPoint(x: screen.maxX - collapsedSize.width - 30,
                             y: screen.minY + 60)

        window = PetWindow(
            contentRect: NSRect(origin: origin, size: collapsedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false

        let root = PetWithPanel(model: model) { [weak self] in
            self?.toggleExpanded()
        }
        let host = ClickableHostingView(rootView: root)
        host.onHit = { [weak self] p in
            self?.handleHit(p, viewHeight: self?.window.frame.height ?? 0) ?? false
        }
        host.onBodyTap = { [weak self] in
            self?.toggleExpanded()
        }
        host.menuProvider = { [weak self] in
            self?.makeMenu() ?? NSMenu()
        }
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: collapsedSize)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()

        // 确保窗口在屏内
        var safe = window.frame
        safe.origin.x = max(screen.minX, min(safe.origin.x, screen.maxX - collapsedSize.width))
        safe.origin.y = max(screen.minY, min(safe.origin.y, screen.maxY - collapsedSize.height))
        window.setFrameOrigin(safe.origin)

        window.makeKeyAndOrderFront(nil)
        model.window = window

        // 测试用：PET_POS="x,y" 启动时定位
        if let pos = ProcessInfo.processInfo.environment["PET_POS"] {
            let parts = pos.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                window.setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
            }
        }
        AppDelegate.shared = self

        // 调试：PET_EXPANDED=1 启动即展开
        if ProcessInfo.processInfo.environment["PET_EXPANDED"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.toggleExpanded()
            }
        }
        window.contentView?.needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            host.needsDisplay = true
        }

        let f = window.frame
    }

    /// 根据提示气泡与展开状态调整窗口尺寸，底部锚点不动
    /// 处理视图内点击（AppKit 坐标，原点左下）
    private func handleHit(_ p: NSPoint, viewHeight: CGFloat) -> Bool {
        guard model.isExpanded else { return false }
        // SwiftUI 的 global 坐标原点在左上；转成 AppKit 的「原点左上」比较
        let sx = p.x
        let sy = viewHeight - p.y        // 转成原点左上

        let active = Array(model.sessions.filter { !$0.isDone }.prefix(8))
        for f in model.rowFrames {
            guard f.index >= 0, f.index < active.count else { continue }
            let r = f.rect
            if sx >= r.minX, sx <= r.maxX, sy >= r.minY, sy <= r.maxY {
                let target = active[f.index]
                SessionJump.focus(pid: target.pid)
                return true
            }
        }
        return false
    }

    private func applySize(hasNotice: Bool) {
        guard !model.isExpanded else { return }
        let base = collapsedSize
        let target = hasNotice
            ? NSSize(width: max(base.width, noticeSize.width),
                     height: base.height + (noticeSize.height - base.height))
            : base
        guard abs(window.frame.height - target.height) > 0.5 else { return }

        var frame = window.frame
        let bottomRight = NSPoint(x: frame.maxX, y: frame.minY)
        frame.size = target
        frame.origin = NSPoint(x: bottomRight.x - target.width, y: bottomRight.y)

        let screen = window.screen?.visibleFrame ?? .zero
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }

        window.setFrame(frame, display: true)
    }

    /// 展开 / 收起，窗口随内容变大变小，锚点保持在右下角
    private func toggleExpanded() {
        let target = model.isExpanded ? collapsedSize : expandedSize
        var frame = window.frame
        let bottomRight = NSPoint(x: frame.maxX, y: frame.minY)

        model.isExpanded.toggle()
        if model.isExpanded {
            model.refreshSessions()
        }

        frame.size = target
        frame.origin = NSPoint(x: bottomRight.x - target.width, y: bottomRight.y)

        // 别跑出屏幕
        let screen = window.screen?.visibleFrame ?? .zero
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: 右键菜单

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let expand = NSMenuItem(title: "展开会话面板", action: #selector(expandPanel), keyEquivalent: "e")
        expand.target = self
        menu.addItem(expand)

        let walk = NSMenuItem(title: "开始走动", action: #selector(toggleWalk(_:)), keyEquivalent: "")
        walk.target = self
        menu.addItem(walk)

        let corner = NSMenuItem(title: "回到右下角", action: #selector(recenter), keyEquivalent: "")
        corner.target = self
        menu.addItem(corner)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出宠物", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func quitApp() {
        model.isExpanded = false
        NSApp.terminate(nil)
    }

    @objc private func expandPanel() {
        if !model.isExpanded { toggleExpanded() }
    }

    @objc private func toggleWalk(_ item: NSMenuItem) {
        if isWalking {
            walkTimer?.invalidate(); walkTimer = nil
            isWalking = false
            item.title = "开始走动"
        } else {
            isWalking = true
            item.title = "停止走动"
            startWalking()
        }
    }

    @objc private func recenter() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: screen.maxX - collapsedSize.width - 40, y: screen.minY + 40))
    }

    // MARK: 随机走动（展开时不走）

    private func startWalking() {
        func step() {
            guard isWalking, !model.isExpanded else {
                walkTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in step() }
                return
            }
            // 在所有屏幕的底部条带里随机挑一个落点
            let w = window.frame.width
            let h = window.frame.height
            let screens = NSScreen.screens.map { $0.visibleFrame }
            guard let screen = screens.randomElement() else { return }
            let maxX = max(screen.minX, screen.maxX - w)
            let lowY = screen.minY
            let highY = min(screen.maxY - h, screen.minY + 200)
            let target = NSPoint(
                x: CGFloat.random(in: screen.minX...maxX),
                y: CGFloat.random(in: lowY...max(lowY, highY))
            )
            model.facing = target.x >= window.frame.origin.x ? 1 : -1

            slideWindow(to: target, seconds: Double.random(in: 3.5...6.0)) { [weak self] _ in
                self?.walkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 10...18),
                                                       repeats: false) { _ in step() }
            }
        }
        walkTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in step() }
    }

    /// 逐帧移动窗口。无边框窗口上 NSAnimationContext 不可靠，自己算帧更稳。
    private func slideWindow(to target: NSPoint, seconds: Double, done: @escaping (Bool) -> Void) {
        let start = window.frame.origin
        let startTime = ProcessInfo.processInfo.systemUptime
        var frameTimer: Timer?

        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            let raw = min(1.0, elapsed / seconds)
            // easeInOut
            let t = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2

            let x = start.x + (target.x - start.x) * t
            let y = start.y + (target.y - start.y) * t
            self.window.setFrameOrigin(NSPoint(x: x, y: y))

            if raw >= 1.0 {
                timer.invalidate()
                done(true)
            }
        }
        walkFrameTimer = frameTimer
    }

    static weak var shared: AppDelegate?

    /// 主屏可见区域
    func primaryFrame() -> NSRect { primaryScreen() }

    /// 主屏：有菜单栏的那块（frame 原点为 0,0）
    private func primaryScreen() -> NSRect {
        // 有菜单栏的那块屏：frame 原点为 (0,0)。
        // 不用 NSScreen.main——它会跟着焦点或鼠标跑，多屏时不可靠。
        let s = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
        return s?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func playDoneSound() {
        NSSound(named: "Glass")?.play()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
