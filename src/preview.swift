import Cocoa
import SwiftUI

// 把 SwiftUI 视图离屏渲染成 PNG，用于自检外观。

func render<V: View>(_ view: V, size: NSSize, scale: CGFloat = 2, to path: String) {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    let win = NSWindow(
        contentRect: NSRect(x: -12000, y: -12000, width: size.width, height: size.height),
        styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    win.isOpaque = true
    win.backgroundColor = .white
    win.orderFrontRegardless()
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))

    let px = NSSize(width: size.width * scale, height: size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width),
        pixelsHigh: Int(px.height), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    host.displayIgnoringOpacity(host.bounds, in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    win.orderOut(nil)

    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(Int(px.width))x\(Int(px.height))")
}

// 一张对照表：6 种情绪
struct MoodSheet: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                cell("空闲", WhaleMood())
                cell("思考", WhaleMood(eyeStyle: .open, mouth: .small, blush: 0.4))
                cell("干活", WhaleMood(eyeStyle: .sparkle, mouth: .open, blush: 0.8))
            }
            HStack(spacing: 8) {
                cell("完成", WhaleMood(eyeStyle: .happy, mouth: .open, blush: 0.95))
                cell("累了", WhaleMood(eyeStyle: .sleepy, mouth: .wobble, blush: 0.3))
                cell("出错", WhaleMood(eyeStyle: .dizzy, mouth: .wobble, blush: 0.2))
            }
        }
        .padding(16)
        .background(Color(white: 0.94))
    }

    func cell(_ label: String, _ mood: WhaleMood) -> some View {
        VStack(spacing: 4) {
            WhaleGirl(mood: mood)
                .frame(width: 100, height: 100)
            Text(label).font(.system(size: 13)).foregroundColor(.black.opacity(0.6))
        }
        .frame(width: 130, height: 136)
        .background(Color.white)
        .cornerRadius(12)
    }
}

func runPreview() {
    let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "moods"
    let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/whale.png"

    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    switch mode {
    case "moods":
        render(MoodSheet(), size: NSSize(width: 434, height: 300), scale: 2, to: out)
    case "panel":
    let rows = SessionReader.readAll().map {
        SessionRow(id: $0.id, name: $0.name, cwd: $0.cwd,
                   status: $0.status, lastPrompt: $0.lastPrompt,
                   updatedAt: $0.updatedAt, isDone: false)
    }
    render(SessionPanel(sessions: Array(rows.prefix(7)), onClose: {}),
           size: NSSize(width: 268, height: 430), scale: 2, to: out)
case "single":
        render(
            WhaleGirl(mood: WhaleMood())
                .frame(width: 100, height: 100)
                .padding(20)
                .background(Color(white: 0.95)),
            size: NSSize(width: 140, height: 140), scale: 3, to: out
        )
    default:
        print("usage: preview [moods|single] [out.png]")
    }

}
