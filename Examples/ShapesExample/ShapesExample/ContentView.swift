import Observation
import PencilKit
import Shapes
import SwiftUI

struct ContentView: View {
    @State private var model = CanvasModel()

    var body: some View {
        NavigationStack {
            CanvasView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay {
                    if model.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "applepencil.and.scribble")
                                .font(.largeTitle)
                            Text("Draw a shape, pause, then lift to snap")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .animation(.default, value: model.isEmpty)
                .navigationTitle("Shapes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { model.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!model.canUndo)

                        Button { model.redo() } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!model.canRedo)

                        Button(role: .destructive) { model.clear() } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(model.isEmpty)
                    }
                }
        }
    }
}

/// Holds the canvas and mirrors its undo/empty state for the toolbar.
@Observable
final class CanvasModel: NSObject, PKCanvasViewDelegate {
    var canUndo = false
    var canRedo = false
    var isEmpty = true

    @ObservationIgnored weak var canvas: PKCanvasView?

    func undo() { canvas?.undoManager?.undo(); refresh() }
    func redo() { canvas?.undoManager?.redo(); refresh() }

    func clear() {
        guard let canvas, !canvas.drawing.strokes.isEmpty else { return }
        setDrawing(PKDrawing(), on: canvas)
        refresh()
    }

    func canvasViewDrawingDidChange(_: PKCanvasView) { refresh() }

    func refresh() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
        isEmpty = canvas?.drawing.strokes.isEmpty ?? true
    }

    private func setDrawing(_ drawing: PKDrawing, on canvas: PKCanvasView) {
        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: self) { model in
            guard let canvas = model.canvas else { return }
            model.setDrawing(previous, on: canvas)
            model.refresh()
        }
        canvas.drawing = drawing
    }
}

/// A PencilKit canvas with the system tool picker and one-line shape snapping.
struct CanvasView: UIViewRepresentable {
    var model: CanvasModel

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 7)
        canvas.alwaysBounceVertical = true

        // Order matters: set our delegate first, then enable snapping (it wraps
        // and forwards to the existing delegate).
        canvas.delegate = model
        canvas.enableShapeSnapping()

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.toolPicker = picker

        model.canvas = canvas
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            model.refresh()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context _: Context) {
        if !canvas.isFirstResponder { canvas.becomeFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var toolPicker: PKToolPicker?
    }
}

#Preview {
    ContentView()
}
