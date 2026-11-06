import SwiftUI
import AppKit

// MARK: - 鲸鱼娘（图片素材版）
//
// 角色素材取自开源表情包合集 deepseek-chan-meme-pack（非营利粉丝向）。
// 状态通过轻微缩放 / 位移 / 亮度表现，不做任何色块叠加。

struct WhaleMood {
    var eye: EyeKind = .open
    var isBlinking = false
    var bob: CGFloat = 0
}

enum EyeKind { case open, happy, closed, sleepy, dizzy, sparkle }

// MARK: - 素材加载

final class PetAssets {
    static let shared = PetAssets()

    private(set) var whale: NSImage?

    private init() {
        whale = load("whale")
    }

    private func load(_ name: String) -> NSImage? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("assets/\(name).png"),
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("assets/\(name).png"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/pet-desktop/assets/\(name).png"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let img = NSImage(contentsOf: url) { return img }
        }
        return nil
    }
}

// MARK: - 角色视图

struct WhaleGirl: View {
    let mood: WhaleMood

    private var image: NSImage? { PetAssets.shared.whale }

    /// 各状态的视觉变换：(缩放, 旋转, 垂直位移, 亮度偏移, 饱和度)
    private var fx: (scale: CGFloat, rot: Double, dy: CGFloat, brightness: Double, saturation: Double) {
        switch mood.eye {
        case .sparkle: return (1.05, -2, -1.5,  0.00, 1.00)   // 干活
        case .happy:   return (1.09,  0, -4.0,  0.03, 1.05)   // 完成
        case .sleepy:  return (0.97,  1,  2.0, -0.10, 0.80)   // 累
        case .dizzy:   return (0.98, -5,  0.0, -0.06, 0.85)   // 出错
        case .closed:  return (1.00,  0,  0.0, -0.03, 0.95)
        case .open:    return (1.00,  0,  0.0,  0.00, 1.00)
        }
    }

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(fx.scale)
                    .rotationEffect(.degrees(fx.rot))
                    .offset(y: fx.dy + mood.bob)
                    .brightness(fx.brightness)
                    .saturation(fx.saturation)
            } else {
                ZStack {
                    Circle().fill(Color(red: 0.44, green: 0.72, blue: 0.97))
                        .frame(width: 90, height: 90)
                    Text("🐋").font(.system(size: 46))
                }
            }
        }
        .frame(width: 150, height: 118)
    }
}
