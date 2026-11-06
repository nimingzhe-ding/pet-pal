import Cocoa

// 白底抠图 v2：从四边泛洪（flood fill）只去掉连通的背景，
// 角色内部的白色（眼睛高光、白裙子）保留下来。
// 用法: cutout <src.png> <dst.png> [x y w h] [阈值]

func run() {
    let a = CommandLine.arguments
    guard a.count >= 3 else { print("usage: cutout src dst [x y w h] [thr]"); exit(1) }

    guard let img = NSImage(contentsOfFile: a[1]),
          let tiff = img.tiffRepresentation,
          let srcRep = NSBitmapImageRep(data: tiff)
    else { print("load fail"); return }

    let W = srcRep.pixelsWide, H = srcRep.pixelsHigh
    guard let flat = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: W * 4, bitsPerPixel: 32
    ), let sp = flat.bitmapData else { print("alloc fail"); return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flat)
    srcRep.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
    NSGraphicsContext.restoreGraphicsState()

    var cx = 0, cy = 0, cw = W, ch = H
    if a.count >= 7, let x = Int(a[3]), let y = Int(a[4]),
       let w = Int(a[5]), let h = Int(a[6]) {
        cx = max(0, x); cy = max(0, y)
        cw = min(w, W - cx); ch = min(h, H - cy)
    }
    var thr = 232
    if a.count >= 8, let t = Int(a[7]) { thr = t }

    print("src \(W)x\(H) crop \(cx),\(cy) \(cw)x\(ch) thr=\(thr)")
    let bpr = flat.bytesPerRow

    // 判定「接近白」：三通道都 >= thr
    func isWhite(_ x: Int, _ y: Int) -> Bool {
        let i = (cy + y) * bpr + (cx + x) * 4
        return Int(sp[i]) >= thr && Int(sp[i+1]) >= thr && Int(sp[i+2]) >= thr
    }

    // 泛洪：从四条边出发，标记连通的背景
    var bg = [Bool](repeating: false, count: cw * ch)
    var stack: [(Int, Int)] = []
    for x in 0..<cw { stack.append((x, 0)); stack.append((x, ch - 1)) }
    for y in 0..<ch { stack.append((0, y)); stack.append((cw - 1, y)) }

    while let (x, y) = stack.popLast() {
        guard x >= 0, y >= 0, x < cw, y < ch else { continue }
        let k = y * cw + x
        if bg[k] { continue }
        guard isWhite(x, y) else { continue }
        bg[k] = true
        stack.append((x+1, y)); stack.append((x-1, y))
        stack.append((x, y+1)); stack.append((x, y-1))
    }

    // 输出
    guard let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: cw * 4, bitsPerPixel: 32
    ), let op = out.bitmapData else { print("out fail"); return }
    let obpr = out.bytesPerRow

    var cleared = 0
    for y in 0..<ch {
        for x in 0..<cw {
            let si = (cy + y) * bpr + (cx + x) * 4
            let di = y * obpr + x * 4
            let r = Int(sp[si]), g = Int(sp[si+1]), b = Int(sp[si+2])

            var alpha = 255
            if bg[y * cw + x] {
                alpha = 0
                cleared += 1
            } else {
                // 紧挨背景的边缘像素：按亮度做柔化，避免硬边
                let nearBg =
                    (x > 0 && bg[y*cw + x-1]) || (x < cw-1 && bg[y*cw + x+1]) ||
                    (y > 0 && bg[(y-1)*cw + x]) || (y < ch-1 && bg[(y+1)*cw + x])
                if nearBg {
                    let mn = min(r, min(g, b))
                    if mn > thr - 26 {
                        let t = Double(mn - (thr - 26)) / 26.0
                        alpha = Int(max(30, 255.0 * (1.0 - t * 0.85)))
                    }
                }
            }

            op[di] = UInt8(r); op[di+1] = UInt8(g); op[di+2] = UInt8(b); op[di+3] = UInt8(alpha)
        }
    }
    print("cleared \(cleared) px (\(cleared * 100 / (cw*ch))%)")

    guard let png = out.representation(using: .png, properties: [:]) else { print("png fail"); return }
    try? png.write(to: URL(fileURLWithPath: a[2]))
    print("wrote \(a[2])")
}

run()
