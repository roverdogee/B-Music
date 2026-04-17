import AppKit
import Foundation

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func playfulFont(size: CGFloat) -> NSFont {
    NSFont(name: "MarkerFelt-Wide", size: size)
        ?? NSFont(name: "ChalkboardSE-Bold", size: size)
        ?? NSFont(name: "AvenirNext-Heavy", size: size)
        ?? .systemFont(ofSize: size, weight: .heavy)
}

func drawText(_ text: String, fontSize: CGFloat, at point: CGPoint, fill: NSColor, stroke: NSColor, strokeWidth: CGFloat, shadowOffset: CGSize, rotation: CGFloat = 0) {
    let font = playfulFont(size: fontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: fill,
        .strokeColor: stroke,
        .strokeWidth: strokeWidth,
        .paragraphStyle: paragraph
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let shadow = NSShadow()
    shadow.shadowColor = color(20, 107, 143, 0.45)
    shadow.shadowOffset = shadowOffset
    shadow.shadowBlurRadius = 0
    NSGraphicsContext.current?.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: point.x, yBy: point.y + textSize.height / 2)
    transform.rotate(byDegrees: rotation)
    transform.translateX(by: -point.x, yBy: -(point.y + textSize.height / 2))
    transform.concat()
    shadow.set()
    attributed.draw(in: CGRect(x: point.x - textSize.width / 2, y: point.y, width: textSize.width, height: textSize.height))
    NSGraphicsContext.current?.restoreGraphicsState()
}

func drawBouncyWord(_ text: String, fontSize: CGFloat, center: CGPoint) {
    let letters = Array(text)
    let font = playfulFont(size: fontSize)
    let stroke = color(46, 159, 205)
    let fills: [NSColor] = [
        .white,
        color(116, 220, 246),
        .white,
        color(255, 238, 157),
        .white
    ]
    let rotations: [CGFloat] = [-8, 5, -3, 7, -5]
    let yOffsets: [CGFloat] = [10, -10, 4, -12, 8]
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .strokeColor: stroke,
        .strokeWidth: -7
    ]

    let widths = letters.map { NSAttributedString(string: String($0), attributes: attributes).size().width }
    let totalWidth = widths.reduce(0, +) + CGFloat(max(0, letters.count - 1)) * -4
    var x = center.x - totalWidth / 2

    for index in letters.indices {
        let letter = String(letters[index])
        let fill = fills[index % fills.count]
        let attributed = NSAttributedString(string: letter, attributes: [
            .font: font,
            .foregroundColor: fill,
            .strokeColor: stroke,
            .strokeWidth: -7
        ])
        let letterSize = attributed.size()
        let drawPoint = CGPoint(x: x + letterSize.width / 2, y: center.y + yOffsets[index % yOffsets.count])
        let shadow = NSShadow()
        shadow.shadowColor = color(17, 112, 151, 0.45)
        shadow.shadowOffset = CGSize(width: 0, height: -16)
        shadow.shadowBlurRadius = 0

        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: drawPoint.x, yBy: drawPoint.y + letterSize.height / 2)
        transform.rotate(byDegrees: rotations[index % rotations.count])
        transform.translateX(by: -letterSize.width / 2, yBy: -letterSize.height / 2)
        transform.concat()
        shadow.set()
        attributed.draw(at: .zero)
        NSGraphicsContext.current?.restoreGraphicsState()

        x += letterSize.width - 4
    }
}

func drawNote(_ note: String, fontSize: CGFloat, center: CGPoint, rotation: CGFloat, color noteColor: NSColor) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: noteColor]
    let attributed = NSAttributedString(string: note, attributes: attributes)
    let noteSize = attributed.size()

    NSGraphicsContext.current?.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: rotation)
    transform.translateX(by: -noteSize.width / 2, yBy: -noteSize.height / 2)
    transform.concat()
    attributed.draw(at: .zero)
    NSGraphicsContext.current?.restoreGraphicsState()
}

image.lockFocus()

NSGradient(colors: [
    color(248, 111, 154),
    color(242, 77, 128),
    color(231, 57, 114)
])?.draw(in: CGRect(origin: .zero, size: size), angle: 315)

color(255, 255, 255, 0.10).setFill()
NSBezierPath(ovalIn: CGRect(x: -140, y: 690, width: 420, height: 420)).fill()
NSBezierPath(ovalIn: CGRect(x: 760, y: -120, width: 360, height: 360)).fill()

drawNote("♪", fontSize: 92, center: CGPoint(x: 164, y: 800), rotation: -18, color: color(255, 230, 154, 0.9))
drawNote("♫", fontSize: 74, center: CGPoint(x: 840, y: 746), rotation: 12, color: color(255, 255, 255, 0.85))
drawNote("♪", fontSize: 78, center: CGPoint(x: 838, y: 206), rotation: 16, color: color(255, 235, 167, 0.85))
drawNote("♫", fontSize: 58, center: CGPoint(x: 180, y: 226), rotation: -10, color: color(255, 255, 255, 0.78))

drawText("B", fontSize: 390, at: CGPoint(x: 510, y: 430), fill: color(89, 211, 244), stroke: .white, strokeWidth: -10, shadowOffset: CGSize(width: 0, height: -30), rotation: -5)
drawBouncyWord("Music", fontSize: 206, center: CGPoint(x: 512, y: 228))

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Unable to render icon")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try pngData.write(to: outputURL, options: .atomic)
