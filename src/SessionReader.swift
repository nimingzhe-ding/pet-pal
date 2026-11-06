import Foundation

// MARK: - 会话读取

struct SessionInfo: Identifiable {
    let id: String
    var pid: Int
    var name: String
    var cwd: String
    var status: String
    var updatedAt: Double
    var lastPrompt: String
    var isDone: Bool
}

enum SessionReader {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// 读 ~/.claude/sessions/*.json，并补齐标题与最后一条提示
    static func readAll(includeDone: Bool = true) -> [SessionInfo] {
        let dir = home.appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }

        var out: [SessionInfo] = []
        for f in files where f.hasSuffix(".json") {
            let url = dir.appendingPathComponent(f)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // 跳过没有 sessionId 的辅助文件
            guard let sid = obj["sessionId"] as? String else { continue }

            let status = obj["status"] as? String ?? "idle"
            let updatedAt = (obj["updatedAt"] as? Double) ?? 0
            let cwd = obj["cwd"] as? String ?? ""

            var name = obj["name"] as? String ?? ""
            var prompt = ""

            // 从 projects 里找同名 jsonl 补标题与最后提示
            if let meta = readMeta(sessionId: sid) {
                if !meta.title.isEmpty { name = meta.title }
                prompt = meta.lastPrompt
            }
            if name.isEmpty { name = String(sid.prefix(8)) }

            // 判定「已完成」：busy 之外的会话，且已安静超过 3 分钟
            let nowMs = Date().timeIntervalSince1970 * 1000
            let idleMs = nowMs - updatedAt
            let isDone = (status != "busy") && idleMs > 3 * 60 * 1000

            let pid = (obj["pid"] as? Int) ?? 0

            out.append(
                SessionInfo(
                    id: sid,
                    pid: pid,
                    name: name,
                    cwd: cwd,
                    status: status,
                    updatedAt: updatedAt,
                    lastPrompt: prompt,
                    isDone: isDone
                )
            )
        }

        // 按最近活跃排序
        out.sort { $0.updatedAt > $1.updatedAt }
        return out
    }

    /// 从会话的 jsonl 里读 custom-title / agent-name / last-prompt
    private static func readMeta(sessionId: String) -> (title: String, lastPrompt: String)? {
        let projects = home.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projects.path) else {
            return nil
        }

        for d in dirs {
            let file = projects.appendingPathComponent(d).appendingPathComponent("\(sessionId).jsonl")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            return parseMeta(file)
        }
        return nil
    }

    /// 只读文件尾部若干行，够拿标题和最后提示
    private static func parseMeta(_ url: URL) -> (title: String, lastPrompt: String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ("", "") }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let chunk: UInt64 = 256 * 1024
        let start = size > chunk ? size - chunk : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return ("", "") }

        var title = ""
        var lastPrompt = ""

        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            if type == "custom-title", let t = obj["customTitle"] as? String, !t.isEmpty {
                title = t
            } else if type == "agent-name", let t = obj["agentName"] as? String,
                      title.isEmpty, !t.isEmpty {
                title = t
            } else if type == "last-prompt", let p = obj["lastPrompt"] as? String {
                lastPrompt = p
            }
        }
        return (title, lastPrompt)
    }
}
