import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = context
context.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 22, dy: 22), xRadius: 224, yRadius: 224)
NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.095, alpha: 1),
    NSColor(calibratedRed: 0.012, green: 0.020, blue: 0.040, alpha: 1)
])!.draw(in: background, angle: 135)

NSColor(calibratedRed: 0.25, green: 0.44, blue: 0.61, alpha: 0.48).setStroke()
background.lineWidth = 3
background.stroke()

let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 830))
shield.curve(to: NSPoint(x: 780, y: 710), controlPoint1: NSPoint(x: 670, y: 790), controlPoint2: NSPoint(x: 756, y: 756))
shield.curve(to: NSPoint(x: 744, y: 370), controlPoint1: NSPoint(x: 804, y: 575), controlPoint2: NSPoint(x: 792, y: 454))
shield.line(to: NSPoint(x: 512, y: 270))
shield.line(to: NSPoint(x: 280, y: 370))
shield.curve(to: NSPoint(x: 244, y: 710), controlPoint1: NSPoint(x: 232, y: 454), controlPoint2: NSPoint(x: 220, y: 575))
shield.curve(to: NSPoint(x: 512, y: 830), controlPoint1: NSPoint(x: 268, y: 756), controlPoint2: NSPoint(x: 354, y: 790))
shield.close()

NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.55, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.82, blue: 0.57, alpha: 1)
])!.draw(in: shield, angle: 45)

let shackle = NSBezierPath()
shackle.move(to: NSPoint(x: 418, y: 518))
shackle.line(to: NSPoint(x: 418, y: 600))
shackle.curve(to: NSPoint(x: 606, y: 600), controlPoint1: NSPoint(x: 418, y: 704), controlPoint2: NSPoint(x: 606, y: 704))
shackle.line(to: NSPoint(x: 606, y: 518))
shackle.lineCapStyle = .round
shackle.lineJoinStyle = .round
shackle.lineWidth = 46
NSColor(calibratedRed: 0.012, green: 0.075, blue: 0.12, alpha: 0.94).setStroke()
shackle.stroke()

let lockBody = NSBezierPath(roundedRect: NSRect(x: 365, y: 330, width: 294, height: 240), xRadius: 58, yRadius: 58)
NSGradient(colors: [
    NSColor(calibratedRed: 0.025, green: 0.095, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.012, green: 0.045, blue: 0.085, alpha: 1)
])!.draw(in: lockBody, angle: 90)

let keyhole = NSBezierPath(ovalIn: NSRect(x: 482, y: 435, width: 60, height: 60))
NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.80, alpha: 1).setFill()
keyhole.fill()
let keyStem = NSBezierPath(roundedRect: NSRect(x: 500, y: 386, width: 24, height: 72), xRadius: 12, yRadius: 12)
keyStem.fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render app icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
