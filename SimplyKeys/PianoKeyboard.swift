import SwiftUI
import UIKit

/// Native UIKit keyboard for real multitouch, fast drawing, and smooth scrolling.
/// With the lock on, UIScrollView stops intercepting drags so fingers can play glissandos.
struct PianoKeyboard: UIViewRepresentable {
    let sound: SoundEngine
    let clef: Clef
    let spelling: NoteSpelling
    let whiteKeysOnScreen: Double
    let glideLocked: Bool
    let dynamicTouch: Bool
    let accentColor: UIColor

    func makeUIView(context: Context) -> PianoScrollView {
        let view = PianoScrollView()
        view.keys.sound = sound
        view.configure(clef: clef, spelling: spelling,
                       whiteKeysOnScreen: whiteKeysOnScreen, glideLocked: glideLocked,
                       dynamicTouch: dynamicTouch, accentColor: accentColor)
        return view
    }

    func updateUIView(_ view: PianoScrollView, context: Context) {
        view.keys.sound = sound
        view.configure(clef: clef, spelling: spelling,
                       whiteKeysOnScreen: whiteKeysOnScreen, glideLocked: glideLocked,
                       dynamicTouch: dynamicTouch, accentColor: accentColor)
    }
}

final class PianoScrollView: UIScrollView {
    let keys = PianoKeysView()
    private var previousClef: Clef?
    private var initialPlacement = true
    private var pendingStartingNote: Int?
    private var requestedVisibleWhites: Double = 8
    private var pendingScaledCenter: CGFloat?

    init() {
        super.init(frame: .zero)
        alwaysBounceHorizontal = false
        bounces = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        isDirectionalLockEnabled = true
        delaysContentTouches = false
        canCancelContentTouches = true
        contentInsetAdjustmentBehavior = .never
        // Match the keyboard itself rather than UIKit's charcoal system background.
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
        addSubview(keys)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }

    func configure(clef: Clef, spelling: NoteSpelling,
                   whiteKeysOnScreen: Double, glideLocked: Bool,
                   dynamicTouch: Bool, accentColor: UIColor) {
        if keys.dynamicTouch != dynamicTouch {
            keys.releaseAllTouches()
            keys.dynamicTouch = dynamicTouch
        }
        if keys.accentColor.rgbHex != accentColor.rgbHex {
            keys.accentColor = accentColor
            keys.setNeedsDisplay()
        }
        if previousClef != clef {
            previousClef = clef
            pendingStartingNote = clef.startingNote
            keys.releaseAllTouches()
        }

        if keys.spelling != spelling {
            keys.spelling = spelling
            keys.setNeedsDisplay()
        }

        if requestedVisibleWhites != whiteKeysOnScreen {
            requestedVisibleWhites = whiteKeysOnScreen
            setNeedsLayout()
        }

        if isScrollEnabled == glideLocked {
            keys.releaseAllTouches()
            isScrollEnabled = !glideLocked
            keys.glideLocked = glideLocked
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let desiredWidth = bounds.width / CGFloat(requestedVisibleWhites)
        if abs(keys.whiteWidth - desiredWidth) > 0.1 {
            // Keep the same musical location centered while changing the key scale.
            if !initialPlacement && keys.whiteWidth > 0 {
                pendingScaledCenter = (contentOffset.x + bounds.midX) * desiredWidth / keys.whiteWidth
            }
            keys.whiteWidth = desiredWidth
            keys.releaseAllTouches()
        }

        let newSize = CGSize(width: keys.totalWidth, height: bounds.height)
        if keys.frame.size != newSize {
            keys.frame = CGRect(origin: .zero, size: newSize)
            contentSize = newSize
            keys.rebuildGeometry()
        }

        let maxX = max(0, contentSize.width - bounds.width)
        if let note = pendingStartingNote {
            pendingStartingNote = nil
            pendingScaledCenter = nil
            let x = (keys.frameForNote(note)?.minX ?? 0) - bounds.width * 0.28
            setContentOffset(CGPoint(x: min(max(x, 0), maxX), y: 0), animated: false)
            initialPlacement = false
        } else if let center = pendingScaledCenter {
            pendingScaledCenter = nil
            setContentOffset(CGPoint(x: min(max(center - bounds.midX, 0), maxX), y: 0), animated: false)
        }
    }
}

final class PianoKeysView: UIView {
    weak var sound: SoundEngine?
    var spelling: NoteSpelling = .both
    var glideLocked = false
    var dynamicTouch = false
    var accentColor: UIColor = .systemBlue

    // MIDI covers 128 pitches: C-1 through G9 (10 octaves + 8 semitones).
    // This is the full standard MIDI range, rather than inventing unsupported notes.
    private let lowest = 0
    private let highest = 127
    var whiteWidth: CGFloat = 48

    private var noteRects: [Int: CGRect] = [:]
    private struct TouchVoice {
        var note: Int
        let channel: UInt8
        var expression: UInt8
    }
    private var touchNotes: [ObjectIdentifier: TouchVoice] = [:]
    private var keyHolds: [Int: Int] = [:]
    private var pressAmounts: [Int: CGFloat] = [:]
    private var animator: CADisplayLink?
    private var lastAnimationTime: CFTimeInterval = 0

    var totalWidth: CGFloat {
        CGFloat((lowest...highest).filter { !NoteNames.isBlack($0) }.count) * whiteWidth
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        contentMode = .redraw
        accessibilityLabel = "Playable, scrolling keyboard with labeled notes"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    deinit { animator?.invalidate() }

    func rebuildGeometry() {
        let keyHeight = bounds.height
        let sharpWidth = whiteWidth * 0.61
        let sharpHeight = keyHeight * 0.61
        var index = 0
        var output: [Int: CGRect] = [:]

        for midi in lowest...highest {
            if NoteNames.isBlack(midi) {
                let previousEnd = CGFloat(index) * whiteWidth
                output[midi] = CGRect(x: previousEnd - sharpWidth / 2, y: 0,
                                       width: sharpWidth, height: sharpHeight)
            } else {
                output[midi] = CGRect(x: CGFloat(index) * whiteWidth, y: 0,
                                       width: whiteWidth, height: keyHeight)
                index += 1
            }
        }
        noteRects = output
        setNeedsDisplay()
    }

    func frameForNote(_ midi: Int) -> CGRect? { noteRects[midi] }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setNeedsDisplay()
        }
    }

    private func blend(_ from: UIColor, _ to: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }

    override func draw(_ dirtyRect: CGRect) {
        let dark = traitCollection.userInterfaceStyle == .dark
        // True black in dark mode, true white in light mode (no tinted gray).
        let background: UIColor = dark ? .black : .white
        let natural: UIColor = dark ? .black : .white
        let foreground = dark ? UIColor(white: 0.96, alpha: 1) : UIColor(white: 0.13, alpha: 1)
        let separators = dark ? UIColor(white: 0.72, alpha: 0.25) : UIColor(white: 0.38, alpha: 0.35)
        let blue = accentColor.resolvedColor(with: traitCollection)
        // Accidentals invert to the neutral theme color when held.
        let pressedSharp: UIColor = dark ? .black : .white

        background.setFill()
        UIRectFill(dirtyRect)

        // Natural keys form the bottom layer. The blue accidentals are on top.
        for midi in lowest...highest where !NoteNames.isBlack(midi) {
            guard let rect = noteRects[midi], rect.intersects(dirtyRect) else { continue }
            let press = pressAmounts[midi, default: 0]
            let travel = press * 4
            let moved = rect.insetBy(dx: 0.55, dy: 1).offsetBy(dx: 0, dy: travel)
            let shape = UIBezierPath(roundedRect: moved, cornerRadius: min(6, whiteWidth * 0.1))
            blend(natural, blue, amount: press).setFill()
            shape.fill()
            separators.setStroke()
            shape.lineWidth = 0.9
            shape.stroke()

            let name = NoteNames.label(for: midi, spelling: spelling, compact: whiteWidth < 37)
            let labelColor = blend(foreground, AccentPalette.textColor(on: blue), amount: press)
            drawLabel(name,
                      in: CGRect(x: rect.minX + 1, y: rect.maxY - 59 + travel,
                                 width: rect.width - 2, height: 25),
                      color: labelColor,
                      size: min(15, max(8.3, whiteWidth * 0.27)), weight: .medium)
        }

        for midi in lowest...highest where NoteNames.isBlack(midi) {
            guard let rect = noteRects[midi], rect.intersects(dirtyRect) else { continue }
            let press = pressAmounts[midi, default: 0]
            let travel = press * 5
            let moved = rect.insetBy(dx: 0.7, dy: 1).offsetBy(dx: 0, dy: travel)
            let shape = UIBezierPath(roundedRect: moved,
                                     cornerRadius: min(7, whiteWidth * 0.13))
            blend(blue, pressedSharp, amount: press).setFill()
            shape.fill()
            blend(.white.withAlphaComponent(0.2), blue.withAlphaComponent(0.7), amount: press).setStroke()
            shape.lineWidth = 1
            shape.stroke()

            let compact = whiteWidth < 57
            let label = NoteNames.label(for: midi, spelling: spelling, compact: compact)
            let numberOfLines = label.contains("\n") ? 2 : 1
            let labelHeight: CGFloat = numberOfLines == 2 ? 37 : 24
            let labelColor = blend(AccentPalette.textColor(on: blue), foreground, amount: press)
            drawLabel(label,
                      in: CGRect(x: rect.minX + 0.5,
                                 y: rect.maxY - labelHeight - 20 + travel,
                                 width: rect.width - 1, height: labelHeight),
                      color: labelColor,
                      size: min(12, max(7.5, whiteWidth * (numberOfLines == 2 ? 0.16 : 0.22))),
                      weight: .semibold)
        }
    }

    private func drawLabel(_ string: String, in rect: CGRect,
                           color: UIColor, size: CGFloat, weight: UIFont.Weight) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 0
        let text = NSAttributedString(string: string, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        text.draw(in: rect)
    }

    private func midi(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        // Sharp/flat keys get first refusal in overlapping hit regions.
        for midi in lowest...highest where NoteNames.isBlack(midi) {
            if noteRects[midi]?.contains(point) == true { return midi }
        }
        for midi in lowest...highest where !NoteNames.isBlack(midi) {
            if noteRects[midi]?.contains(point) == true { return midi }
        }
        return nil
    }

    private func redraw(_ midi: Int) {
        if let rect = noteRects[midi] {
            setNeedsDisplay(rect.insetBy(dx: -3, dy: -8))
        }
    }

    private func ensureAnimation() {
        guard animator == nil else { return }
        lastAnimationTime = 0
        let link = CADisplayLink(target: self, selector: #selector(animateKeys(_:)))
        link.add(to: .main, forMode: .common)
        animator = link
    }

    @objc private func animateKeys(_ link: CADisplayLink) {
        let seconds = lastAnimationTime == 0 ? 1.0 / 60.0 : min(0.05, link.timestamp - lastAnimationTime)
        lastAnimationTime = link.timestamp
        let speed: CGFloat = CGFloat(min(1, seconds * 22))
        var needsAnotherFrame = false
        for midi in Array(pressAmounts.keys) {
            let current = pressAmounts[midi, default: 0]
            let target: CGFloat = keyHolds[midi, default: 0] > 0 ? 1 : 0
            let next = current + (target - current) * speed
            if abs(next - target) < 0.015 {
                if target == 0 { pressAmounts.removeValue(forKey: midi) }
                else { pressAmounts[midi] = 1 }
            } else {
                pressAmounts[midi] = next
                needsAnotherFrame = true
            }
            redraw(midi)
        }
        if !needsAnotherFrame {
            animator?.invalidate()
            animator = nil
        }
    }

    /// The hinge is quiet; the bottom edge is loud. Expression controller 11
    /// keeps changes smooth on the same key without retriggering the note.
    private func expression(at location: CGPoint, note: Int) -> UInt8 {
        guard dynamicTouch else { return 103 } // Mezzo-forte when disabled
        // Normalize within the actual touched key: blue accidentals are shorter.
        // Moving below a blue key still means full forte for that same held note.
        let height = max(1, noteRects[note]?.height ?? bounds.height)
        let progress = min(1, max(0, Double(location.y / height)))
        return UInt8(clamping: Int((24 + 103 * pow(progress, 1.45)).rounded()))
    }

    private func availableChannel() -> UInt8? {
        let used = Set(touchNotes.values.map(\.channel))
        return SoundEngine.touchChannels.first { !used.contains($0) }
    }

    private func begin(_ note: Int, channel: UInt8, level: UInt8) {
        keyHolds[note, default: 0] += 1
        // The display-link only animates notes already in pressAmounts.
        // Seed every new press so it gets its first frame, even on a quick tap.
        pressAmounts[note] = max(pressAmounts[note, default: 0], 0.3)
        sound?.expression(level, channel: channel)
        // Velocity selects recorded layers; expression adjusts sustained volume.
        sound?.noteOn(note, velocity: dynamicTouch ? level : 100, channel: channel)
        ensureAnimation()
        redraw(note)
    }

    private func finish(_ note: Int, channel: UInt8) {
        let count = keyHolds[note, default: 0]
        guard count > 0 else { return }
        if count == 1 { keyHolds.removeValue(forKey: note) }
        else { keyHolds[note] = count - 1 }
        sound?.noteOff(note, channel: channel)
        ensureAnimation()
        redraw(note)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let location = touch.location(in: self)
            guard let note = midi(at: location), let channel = availableChannel() else { continue }
            let level = expression(at: location, note: note)
            touchNotes[ObjectIdentifier(touch)] = TouchVoice(note: note, channel: channel, expression: level)
            begin(note, channel: channel, level: level)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let identity = ObjectIdentifier(touch)
            guard var voice = touchNotes[identity] else { continue }
            let location = touch.location(in: self)
            // When gliding, use the NEXT key's own height for its dynamics.
            let nextNote = glideLocked ? (midi(at: location) ?? voice.note) : voice.note
            let level = expression(at: location, note: nextNote)
            if glideLocked && nextNote != voice.note {
                finish(voice.note, channel: voice.channel)
                begin(nextNote, channel: voice.channel, level: level)
                voice.note = nextNote
            } else if level != voice.expression {
                sound?.expression(level, channel: voice.channel)
            }
            voice.expression = level
            touchNotes[identity] = voice
        }
    }

    private func finishTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if let voice = touchNotes.removeValue(forKey: ObjectIdentifier(touch)) {
                finish(voice.note, channel: voice.channel)
                sound?.expression(127, channel: voice.channel)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        finishTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        finishTouches(touches)
    }

    func releaseAllTouches() {
        for voice in touchNotes.values {
            sound?.noteOff(voice.note, channel: voice.channel)
            sound?.expression(127, channel: voice.channel)
        }
        keyHolds.removeAll()
        touchNotes.removeAll()
        if !pressAmounts.isEmpty { ensureAnimation() }
    }
}
