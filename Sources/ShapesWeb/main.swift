#if os(WASI)
import JavaScriptEventLoop
import JavaScriptKit
@_spi(ShapesBindings) import Shapes

// WebAssembly entry point. Mirrors the iOS/Swift SDK (recognition only). The JS
// host must set `globalThis.__ShapesHost` (an async ONNX session + runner, see
// desert-ant-core's JSInferenceSession) before the first recognition. After
// start, the module exposes:
//
//     globalThis.__ShapesExports = {
//       load(cacheRoot, directory?, onProgress?)   -> Promise<boolean>,
//       recognize(points, minimumConfidence?)      -> Promise<Shape | null>,
//     }
//
// `points` is a flat number array [x0, y0, x1, y1, ...]. A recognized shape is a
// plain object: { kind, ...fields }. `packages/shapes-node` wraps this in the
// public typed API; nothing else should touch these globals.
JavaScriptEventLoop.installGlobalExecutor()

private nonisolated(unsafe) var recognizer: Shapes?
private func instance() throws -> Shapes {
    guard let recognizer else { throw ShapesError.resourceMissing }
    return recognizer
}

private func parsePoints(_ value: JSValue) -> [Point] {
    guard let array = value.object, let n = array.length.number else { return [] }
    let count = Int(n) / 2
    var points: [Point] = []
    points.reserveCapacity(count)
    for i in 0..<count {
        let x = array[i * 2].number ?? 0
        let y = array[i * 2 + 1].number ?? 0
        points.append(Point(x: x, y: y))
    }
    return points
}

private func encode(_ shape: Shape) -> JSValue {
    let o = JSObject.global.Object.function!.new()
    func point(_ p: Point) -> JSValue {
        let po = JSObject.global.Object.function!.new()
        po.x = .number(p.x)
        po.y = .number(p.y)
        return .object(po)
    }
    func points(_ ps: [Point]) -> JSValue {
        let arr = JSObject.global.Array.function!.new()
        for (i, p) in ps.enumerated() { arr[i] = point(p) }
        return .object(arr)
    }
    switch shape {
    case let .line(from, to):
        o.kind = .string("line")
        o.from = point(from)
        o.to = point(to)
    case let .rectangle(corners):
        o.kind = .string("rectangle")
        o.corners = points(corners)
    case let .triangle(vertices):
        o.kind = .string("triangle")
        o.vertices = points(vertices)
    case let .ellipse(center, semiMajor, semiMinor, rotation):
        o.kind = .string("ellipse")
        o.center = point(center)
        o.semiMajor = .number(semiMajor)
        o.semiMinor = .number(semiMinor)
        o.rotation = .number(rotation)
    case let .star(center, outerRadius, innerRadius, rotation, pointCount):
        o.kind = .string("star")
        o.center = point(center)
        o.outerRadius = .number(outerRadius)
        o.innerRadius = .number(innerRadius)
        o.rotation = .number(rotation)
        o.pointCount = .number(Double(pointCount))
    }
    return .object(o)
}

let recognizeFn = JSClosure { args in
    let points = args.first.map(parsePoints) ?? []
    let minimum = args.count > 1 ? (args[1].number ?? 0) : 0
    let options = Options(minimumConfidence: minimum)
    return JSPromise { resolve in
        Task {
            do {
                if let shape = try await instance().recognize(points: points, options: options) {
                    resolve(.success(encode(shape)))
                } else {
                    resolve(.success(.null))
                }
            } catch {
                resolve(.failure(.string(String(describing: error))))
            }
        }
    }.jsValue
}

// load(cacheRoot, directory, onProgress?): the repo and revision are pinned to
// the SDK. `cacheRoot` is the base for the managed nested cache (node `~/.cache`;
// empty in the browser). `directory`, when non-empty, is an explicit model
// directory (adopt files there, else download into it). `onProgress`, when a
// function, is called with the download fraction in [0, 1].
let loadFn = JSClosure { args in
    let cacheRoot = args.first?.string.flatMap { $0.isEmpty ? nil : $0 }
    let directory = (args.count > 1 ? args[1].string : nil).flatMap { $0.isEmpty ? nil : $0 }
    let onProgress: JSFunction? = args.count > 2 ? args[2].function : nil
    let shapes = Shapes(directory: directory, cacheRoot: cacheRoot)
    return JSPromise { resolve in
        Task {
            do {
                try await shapes.download { fraction in
                    if let onProgress { _ = onProgress(fraction) }
                }
                recognizer = shapes
                resolve(.success(.boolean(true)))
            } catch {
                resolve(.failure(.string(String(describing: error))))
            }
        }
    }.jsValue
}

let exports = JSObject.global.Object.function!.new()
exports.load = .object(loadFn)
exports.recognize = .object(recognizeFn)
JSObject.global.__ShapesExports = .object(exports)
#endif
