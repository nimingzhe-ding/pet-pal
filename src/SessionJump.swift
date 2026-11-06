import Cocoa
import Foundation

// MARK: - 会话跳转
//
// 三种来源分别处理：
//   · VS Code 内启动 → 激活 VS Code
//   · Claude.app 内启动 → claude://code 切回 App
//   · 终端内启动 → 激活对应终端 App

enum SessionJump {

    /// 记录调用前的前台 app，用于验证是否切换成功
    static func frontmostName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
    }

    static func focus(pid: Int?) {
        guard let pid, pid > 0 else { return }

        let chain = ancestorChain(of: pid)
        let joined = chain.joined(separator: " ").lowercased()

        // 1. VS Code
        if joined.contains("visual studio code") || joined.contains("code helper") {
            activate(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
            return
        }

        // 2. Claude 桌面 App
        if joined.contains("/applications/claude.app") || joined.contains("claude-3p") {
            if let url = URL(string: "claude://code/continue?session=last") {
                NSWorkspace.shared.open(url)
            }
            activate(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
            return
        }

        // 3. 终端
        for (marker, bundle, name) in [
            ("iterm", "com.googlecode.iterm2", "iTerm"),
            ("warp", "dev.warp.Warp-Stable", "Warp"),
            ("kitty", "net.kovidgoyal.kitty", "kitty"),
            ("alacritty", "org.alacritty", "Alacritty"),
            ("wezterm", "com.github.wez.wezterm", "WezTerm"),
            ("ghostty", "com.mitchellh.ghostty", "Ghostty"),
            ("hyper", "co.zeit.hyper", "Hyper"),
        ] where joined.contains(marker) {
            activate(bundleID: bundle, name: name)
            return
        }

        // 4. 兜底：终端.app
        activate(bundleID: "com.apple.Terminal", name: "Terminal")
    }

    private static func ancestorChain(of pid: Int) -> [String] {
        var names: [String] = []
        var cur = pid
        for _ in 0..<8 {
            guard let out = run("/bin/ps", ["-p", String(cur), "-o", "ppid=,args="]) else { break }
            let line = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { break }
            // 形如 "  1812 /bin/zsh -l"
            let trimmed = line.drop(while: { $0 == " " })
            guard let spaceIdx = trimmed.firstIndex(of: " ") else { break }
            guard let ppid = Int(trimmed[trimmed.startIndex..<spaceIdx]) else { break }
            let comm = String(trimmed[trimmed.index(after: spaceIdx)...])
            names.append(comm)
            if ppid <= 1 { break }
            cur = ppid
        }
        return names
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// 用 NSRunningApplication 激活（比 open -a 更可靠，且能跨 Space）
    static func activate(bundleID: String, name: String) {
        // 先让出自己的激活状态，否则 accessory app 抢不走焦点
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            let ok = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            if !ok {
                // 退一步：用 open -b 让 LaunchServices 处理
                runOpen(bundleID: bundleID)
            }
            return
        }
        runOpen(bundleID: bundleID)
    }

    private static func runOpen(bundleID: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", bundleID]
        try? p.run()
    }
}
