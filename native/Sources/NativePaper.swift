import SwiftUI
import PencilKit
import UIKit

enum NativePaperChange: Equatable { case text, ink, annotation }

struct NativePaper: UIViewRepresentable {
    var page: LocalPage
    var tool: NotebookTool
    var undoSignal: Int
    var redoSignal: Int
    var saved: (NativePaperChange) -> Void

    func makeUIView(context: Context) -> PaperView {
        let view = PaperView()
        view.text.delegate = context.coordinator
        view.canvas.delegate = context.coordinator
        view.mark.onLasso = { [weak view] polygon in
            guard let view else { return }
            context.coordinator.markWords(in: view, polygon: polygon)
        }
        return view
    }
    func updateUIView(_ view: PaperView, context: Context) {
        context.coordinator.parent = self
        if view.text.text != page.text { view.text.text = page.text }
        if view.canvas.drawing.dataRepresentation() != page.ink { view.canvas.drawing = (try? PKDrawing(data: page.ink)) ?? PKDrawing() }
        view.text.isEditable = tool == .type
        view.text.isSelectable = tool == .type || tool == .select
        view.canvas.isUserInteractionEnabled = tool == .write || tool == .erase
        view.canvas.drawingPolicy = PaperInputPolicy.drawingPolicy(for: UIDevice.current.userInterfaceIdiom)
        view.canvas.tool = tool == .erase
            ? PKEraserTool(.vector)
            : PKInkingTool(.pen, color: .sideleafInk, width: 2)
        view.mark.isUserInteractionEnabled = tool == .mark
        if context.coordinator.undoSignal != undoSignal { view.canvas.undoManager?.undo(); context.coordinator.undoSignal = undoSignal }
        if context.coordinator.redoSignal != redoSignal { view.canvas.undoManager?.redo(); context.coordinator.redoSignal = redoSignal }
        view.refreshHighlights(page.annotations)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PaperView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let textHeight = uiView.text.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        let drawingBounds = uiView.canvas.drawing.bounds
        let drawingHeight = drawingBounds.isNull ? 0 : drawingBounds.maxY + 24
        return CGSize(
            width: width,
            height: max(1200, max(ceil(textHeight), ceil(drawingHeight)))
        )
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, PKCanvasViewDelegate {
        var parent: NativePaper
        var undoSignal = 0
        var redoSignal = 0
        init(_ parent: NativePaper) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.page.text = textView.text
            parent.page.textRevision += 1
            parent.page.annotations = parent.page.annotations.map { var mark = $0; mark.anchor = mark.anchor.remapped(to: textView.text, revision: parent.page.textRevision); return mark }
            parent.page.updatedAt = Date(); parent.saved(.text)
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let bytes = canvasView.drawing.dataRepresentation()
            guard bytes != parent.page.ink else { return }
            parent.page.ink = bytes
            // Portable visual artifact only. Native PKDrawing remains editable.
            parent.page.inkPreview = canvasView.drawing.image(from: canvasView.bounds, scale: 1).pngData()
            parent.page.updatedAt = Date(); parent.saved(.ink)
        }
        func markWords(in view: PaperView, polygon: [CGPoint]) {
            guard polygon.count >= 6, let first = polygon.first, let last = polygon.last, hypot(first.x - last.x, first.y - last.y) <= 35 else { return }
            let expression = try! NSRegularExpression(pattern: "\\S+")
            let text = view.text.text ?? ""
            let matches = expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            var ranges: [NSRange] = []
            var current: NSRange?
            for word in matches {
                let glyphRange = view.text.layoutManager.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil)
                var hit = false
                view.text.layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: view.text.textContainer) { rect, _ in
                    let center = CGPoint(x: rect.midX + view.text.textContainerInset.left, y: rect.midY + view.text.textContainerInset.top)
                    if LassoGeometry.contains(view.mark.convert(center, from: view.text), polygon: polygon) { hit = true }
                }
                if hit { current = current.map { NSUnionRange($0, word.range) } ?? word.range }
                else if let range = current { ranges.append(range); current = nil }
            }
            if let current { ranges.append(current) }
            var marks = parent.page.annotations
            for range in ranges where !marks.contains(where: { $0.anchor.resolved && $0.anchor.start == range.location && $0.anchor.end == NSMaxRange(range) }) {
                marks.append(NativeAnnotation(anchor: .make(blockId: parent.page.id, revision: parent.page.textRevision, text: text, range: range)))
            }
            parent.page.annotations = marks; parent.saved(.annotation); view.refreshHighlights(marks)
        }
    }
}

@MainActor
final class PaperView: UIView {
    let text = UITextView(usingTextLayoutManager: false)
    let canvas = PKCanvasView()
    let mark = LassoView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        text.backgroundColor = .clear
        text.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 20)
        )
        text.adjustsFontForContentSizeCategory = true
        text.textColor = .sideleafInk
        text.tintColor = .systemOlive
        text.isScrollEnabled = false
        text.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = PaperInputPolicy.drawingPolicy(for: UIDevice.current.userInterfaceIdiom)
        canvas.isScrollEnabled = false
        mark.backgroundColor = .clear
        [text, canvas, mark].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func layoutSubviews() { super.layoutSubviews(); text.frame = bounds; canvas.frame = bounds; mark.frame = bounds }
    func refreshHighlights(_ marks: [NativeAnnotation]) {
        let length = text.textStorage.length
        guard length > 0 else { return }
        text.textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: length))
        for mark in marks where mark.anchor.resolved && mark.anchor.end <= length {
            text.textStorage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.2), range: NSRange(location: mark.anchor.start, length: mark.anchor.end - mark.anchor.start))
        }
    }
}

@MainActor
final class LassoView: UIView {
    var onLasso: (([CGPoint]) -> Void)?
    private var points: [CGPoint] = []
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { guard let touch = touches.first else { return }; points = [touch.location(in: self)]; setNeedsDisplay() }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { guard let touch = touches.first, points.count < 10000 else { return }; points.append(contentsOf: (event?.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: self) }); setNeedsDisplay() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if let touch = touches.first { points.append(touch.location(in: self)) }; onLasso?(points); points = []; setNeedsDisplay() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { points = []; setNeedsDisplay() }
    override func draw(_ rect: CGRect) { guard let first = points.first else { return }; let path = UIBezierPath(); path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) }; path.lineWidth = 2; UIColor.systemOlive.setStroke(); path.stroke() }
}
enum PaperInputPolicy {
    static func drawingPolicy(for idiom: UIUserInterfaceIdiom) -> PKCanvasViewDrawingPolicy {
        idiom == .phone ? .anyInput : .pencilOnly
    }
}
private extension UIColor {
    static let systemOlive = UIColor(red: 0.41, green: 0.45, blue: 0.33, alpha: 1)
    static let sideleafInk = UIColor(red: 0.04, green: 0.13, blue: 0.23, alpha: 1)
}
