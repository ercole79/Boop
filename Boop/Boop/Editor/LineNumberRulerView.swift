//
//  LineNumberRulerView.swift
//  Boop
//
//  Replaces SavannaKit's LineRulerView. That class fills the dirty rect
//  passed to drawHashMarksAndLabels, which on macOS 14+ can extend past the
//  ruler bounds and paint the gutter (and line numbers) over the whole editor.
//

import Cocoa
import SavannaKit

protocol LineNumberRulerViewDelegate: AnyObject {
    func foldMarkers(for ruler: LineNumberRulerView) -> [FoldMarker]
    func lineNumberRulerView(_ ruler: LineNumberRulerView, didToggleFoldMarker marker: FoldMarker)
}

final class LineNumberRulerView: NSRulerView {

    weak var foldDelegate: LineNumberRulerViewDelegate?

    private weak var textView: NSTextView?
    private var foldHitTargets: [(rect: NSRect, marker: FoldMarker)] = []

    private let foldControlWidth: CGFloat = 14
    private let numberRightInset: CGFloat = 6

    override var isFlipped: Bool {
        true
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        ruleThickness = 52
        installObservers()
        updateThickness()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func installObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateRuler),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateRuler),
            name: NSView.boundsDidChangeNotification,
            object: textView?.enclosingScrollView?.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateRuler),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    @objc private func invalidateRuler() {
        needsDisplay = true
        updateThickness()
    }

    private func currentTheme() -> DefaultTheme {
        return DefaultTheme(appearance: effectiveAppearance)
    }

    private func updateThickness() {
        let lineCount = max(1, (textView?.string.components(separatedBy: .newlines).count) ?? 1)
        let digits = max(2, "\(lineCount)".count)
        let thickness = max(currentTheme().gutterStyle.minimumWidth + foldControlWidth, CGFloat(digits) * 10 + 18 + foldControlWidth)
        if abs(ruleThickness - thickness) > 0.5 {
            ruleThickness = thickness
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in dirtyRect: NSRect) {
        clipsToBounds = true
        foldHitTargets.removeAll(keepingCapacity: true)

        let theme = currentTheme()
        theme.gutterStyle.backgroundColor.setFill()
        bounds.fill()

        if let separatorColor = theme.gutterStyle.separatorColor {
            separatorColor.setStroke()
            let separator = NSBezierPath()
            separator.move(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.minY))
            separator.line(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
            separator.lineWidth = 1
            separator.stroke()
        }

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let numberStyle = theme.lineNumbersStyle
        let font = numberStyle?.font ?? textView.font ?? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let color = numberStyle?.textColor ?? NSColor.secondaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let containerOrigin = textView.textContainerOrigin
        layoutManager.ensureLayout(for: textContainer)

        var visibleRect = textView.visibleRect
        visibleRect.origin.x -= containerOrigin.x
        visibleRect.origin.y -= containerOrigin.y
        if visibleRect.height < 1 {
            visibleRect = NSRect(origin: .zero, size: textContainer.size)
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let nsString = textView.string as NSString
        let markersByLine = Dictionary(
            grouping: foldDelegate?.foldMarkers(for: self) ?? [],
            by: \.lineNumber
        )

        var lineNumber = 1
        if glyphRange.length > 0 {
            let firstVisibleCharacter = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            if firstVisibleCharacter > 0 {
                lineNumber = StructuredTextFolder.lineNumber(at: firstVisibleCharacter, in: nsString)
            }
        }

        func drawLine(_ number: Int, at fragmentRect: CGRect) {
            let pointInTextView = NSPoint(x: 0, y: fragmentRect.minY + containerOrigin.y)
            let pointInRuler = convert(pointInTextView, from: textView)
            let lineHeight = max(fragmentRect.height, font.boundingRectForFont.height)
            let lineRect = NSRect(
                x: bounds.minX,
                y: pointInRuler.y,
                width: bounds.width,
                height: lineHeight
            )

            guard lineRect.intersects(bounds) else {
                return
            }

            if let marker = markersByLine[number]?.first {
                let controlRect = NSRect(
                    x: bounds.minX + 2,
                    y: lineRect.minY + (lineHeight - 12) / 2,
                    width: foldControlWidth,
                    height: 12
                )
                drawFoldControl(marker.isCollapsed, in: controlRect, color: color)
                foldHitTargets.append((controlRect.insetBy(dx: -2, dy: -2), marker))
            }

            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(
                    x: bounds.maxX - size.width - numberRightInset,
                    y: lineRect.minY + max(0, (lineHeight - size.height) / 2)
                ),
                withAttributes: attributes
            )
        }

        if glyphRange.length == 0 {
            drawLine(1, at: CGRect(x: 0, y: 0, width: 0, height: font.boundingRectForFont.height))
            return
        }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, fragmentGlyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: fragmentGlyphRange, actualGlyphRange: nil)
            let paragraphRange = nsString.paragraphRange(for: characterRange)
            guard characterRange.location == paragraphRange.location else {
                return
            }

            drawLine(lineNumber, at: fragmentRect)
            lineNumber += 1
        }

        if nsString.length > 0, nsString.character(at: nsString.length - 1) == 10 || nsString.character(at: nsString.length - 1) == 13 {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                drawLine(lineNumber, at: extraRect)
            }
        }
    }

    private func drawFoldControl(_ isCollapsed: Bool, in rect: NSRect, color: NSColor) {
        let triangle = NSBezierPath()
        let inset: CGFloat = 3
        let body = rect.insetBy(dx: inset, dy: inset)

        if isCollapsed {
            triangle.move(to: NSPoint(x: body.minX, y: body.minY))
            triangle.line(to: NSPoint(x: body.maxX, y: body.midY))
            triangle.line(to: NSPoint(x: body.minX, y: body.maxY))
        } else {
            triangle.move(to: NSPoint(x: body.minX, y: body.minY))
            triangle.line(to: NSPoint(x: body.maxX, y: body.minY))
            triangle.line(to: NSPoint(x: body.midX, y: body.maxY))
        }

        triangle.close()
        color.withAlphaComponent(0.85).setFill()
        triangle.fill()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let target = foldHitTargets.first(where: { $0.rect.contains(point) }) {
            foldDelegate?.lineNumberRulerView(self, didToggleFoldMarker: target.marker)
            return
        }
        super.mouseDown(with: event)
    }
}
