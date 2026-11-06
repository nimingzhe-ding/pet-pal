import SwiftUI

// MARK: - 会话数据

struct SessionRow: Identifiable {
    let id: String
    var pid: Int
    var name: String
    var cwd: String
    var status: String          // idle / busy
    var lastPrompt: String
    var updatedAt: Double
    var isDone: Bool            // 已结束
}

// MARK: - 行位置收集

struct RowFrame: Equatable {
    let index: Int
    let rect: CGRect
}

struct RowFrameKey: PreferenceKey {
    static var defaultValue: [RowFrame] = []
    static func reduce(value: inout [RowFrame], nextValue: () -> [RowFrame]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - 点击捕获层

/// 一个透明的 NSView，用于捕获点击（SwiftUI 手势在无边框窗口里不可靠）
struct ClickCatcher: NSViewRepresentable {
    let onTap: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = ClickView()
        v.onTap = onTap
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClickView)?.onTap = onTap
    }

    final class ClickView: NSView {
        var onTap: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            onTap?()
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - 面板

struct SessionPanel: View {
    let sessions: [SessionRow]
    let onClose: () -> Void
    var onOpen: (SessionRow) -> Void = { _ in }
    var onFrames: ([RowFrame]) -> Void = { _ in }

    private var busyCount: Int { sessions.filter { $0.status == "busy" }.count }
    private var active: [SessionRow] { sessions.filter { !$0.isDone } }
    private var done: [SessionRow] { sessions.filter { $0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            if sessions.isEmpty {
                Text("还没有会话")
                    .font(.custom("PingFang SC", size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(active.prefix(8).enumerated()), id: \.element.id) { idx, s in
                        SessionRowView(row: s, onOpen: onOpen)
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: RowFrameKey.self,
                                        value: [RowFrame(index: idx, rect: g.frame(in: .global))]
                                    )
                                }
                            )
                        Divider().opacity(0.12).padding(.leading, 32)
                    }
                    if !done.isEmpty {
                        HStack(spacing: 5) {
                            Rectangle()
                                .fill(Color(red: 0.30, green: 0.72, blue: 0.45).opacity(0.5))
                                .frame(width: 2.5, height: 9)
                            Text("最近完成")
                                .font(.custom("PingFang SC Medium", size: 9.5))
                                .foregroundColor(Color(red: 0.45, green: 0.51, blue: 0.60))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 9)
                        .padding(.bottom, 4)

                        ForEach(done.prefix(3)) { s in
                            SessionRowView(row: s, onOpen: onOpen)
                            Divider().opacity(0.10).padding(.leading, 32)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 268)
        .onPreferenceChange(RowFrameKey.self) { frames in
            onFrames(frames)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.99, green: 0.995, blue: 1.0))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("🐋").font(.custom("PingFang SC", size: 12))
            Text("会话进度")
                .font(.custom("PingFang SC Semibold", size: 12.5))
                .foregroundColor(Color(red: 0.13, green: 0.16, blue: 0.22))
            Spacer()
            if busyCount > 0 {
                Text("\(busyCount) 进行中")
                    .font(.custom("PingFang SC Medium", size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.36, green: 0.62, blue: 0.95)))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.custom("PingFang SC Semibold", size: 9))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.945, green: 0.965, blue: 0.995))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("共 \(sessions.count) 个")
                .font(.custom("PingFang SC", size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text("右键鲸鱼可收合")
                .font(.custom("PingFang SC", size: 10))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct SessionRowView: View {
    let row: SessionRow
    var onOpen: (SessionRow) -> Void = { _ in }

    @State private var isHovering = false

    private var isBusy: Bool { row.status == "busy" }

    private var accent: Color {
        if row.isDone { return Color(red: 0.30, green: 0.72, blue: 0.45) }
        if isBusy { return Color(red: 0.98, green: 0.62, blue: 0.28) }
        return Color(red: 0.55, green: 0.62, blue: 0.72)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.custom("PingFang SC Medium", size: 12.5))
                        .foregroundColor(Color(red: 0.10, green: 0.13, blue: 0.19))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(timeAgo(row.updatedAt))
                        .font(.custom("PingFang SC", size: 9))
                        .foregroundColor(.secondary.opacity(0.85))
                }
                Text(row.lastPrompt.isEmpty ? "（无提示词）" : row.lastPrompt)
                    .font(.custom("PingFang SC", size: 10))
                    .foregroundColor(Color(red: 0.36, green: 0.41, blue: 0.49))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovering ? Color(red: 0.90, green: 0.94, blue: 1.0) : .clear)
                .padding(.horizontal, 5)
        )
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(row) }
        .help("点击切换到「\(row.name)」")
    }

    private var statusDot: some View {
        ZStack {
            if row.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.custom("PingFang SC", size: 11))
                    .foregroundColor(accent)
            } else if isBusy {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.35), lineWidth: 3.5)
                            .scaleEffect(1.7)
                    )
            } else {
                Circle()
                    .strokeBorder(accent, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 13, height: 13)
        .padding(.top, 1)
    }

    private func timeAgo(_ ms: Double) -> String {
        let secs = (Date().timeIntervalSince1970 * 1000 - ms) / 1000
        if secs < 60 { return "刚刚" }
        if secs < 3600 { return "\(Int(secs / 60))分钟前" }
        if secs < 86400 { return "\(Int(secs / 3600))小时前" }
        return "\(Int(secs / 86400))天前"
    }
}
