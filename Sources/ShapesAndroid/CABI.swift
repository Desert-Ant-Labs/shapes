#if !os(WASI)
@_spi(ShapesBindings) import Shapes
import FFIBuffer
import PlatformSupport

// C ABI over the Shapes core, called by the Swift JNI entry points in
// `AndroidJNI.swift` (and usable from any other host language). Kept
// Foundation-free so the Android build ships without the ~50 MB Foundation/ICU
// stack. Instance-based, mirroring the Swift SDK (one `Shapes` per handle).
//
//   shapes_create(cacheRootUTF8, dirUTF8|NULL)         -> handle | NULL
//   shapes_create_bundled(metaUTF8, model,len)         -> handle | NULL
//   shapes_create_bundled_path(metaUTF8, modelPath)    -> handle | NULL
//   shapes_is_downloaded(handle)                       -> 0/1
//   shapes_download(handle)                            -> 0/-1   (blocks)
//   shapes_run(handle, pointBytes,len, minConf)        -> buffer | NULL
//   shapes_destroy(handle)
//   shapes_string_free(ptr)
//
// Points cross in as little-endian f64 pairs (x0,y0,x1,y1,...). The recognized
// shape comes back as a self-describing binary buffer (no hand-rolled JSON):
// a big-endian uint32 payload length, then u32 present (0/1); if present u32 kind
// (1 line, 2 rectangle, 3 triangle, 4 ellipse, 5 star) followed by that kind's
// fields as f64 (and u32 counts). Coordinates are f64.
//
// The async core API is bridged synchronously here (callers are host-language
// worker threads).

/// A retained box so the opaque handle keeps its `Shapes` alive.
private final class Handle { let shapes: Shapes; init(_ shapes: Shapes) { self.shapes = shapes } }

private func shapes(_ handle: UnsafeMutableRawPointer?) -> Shapes? {
    guard let handle else { return nil }
    return Unmanaged<Handle>.fromOpaque(handle).takeUnretainedValue().shapes
}

/// Create a recognizer. `cacheRoot` is the app cache dir (the base for the
/// managed nested layout). `directory` is an explicit model directory (adopt
/// files there, else download; direct layout), or NULL for the managed nested
/// layout under `cacheRoot`. Loading is lazy, like the Swift SDK.
@_cdecl("shapes_create")
public func shapes_create(
    _ cacheRoot: UnsafePointer<CChar>?, _ directory: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    let shapes = Shapes(
        directory: directory.map { String(cString: $0) },
        cacheRoot: cacheRoot.map { String(cString: $0) })
    return Unmanaged.passRetained(Handle(shapes)).toOpaque()
}

/// Create a recognizer from in-memory bundled model bytes (the Android AAR path).
@_cdecl("shapes_create_bundled")
public func shapes_create_bundled(
    _ metaJSON: UnsafePointer<CChar>?,
    _ model: UnsafePointer<UInt8>?, _ modelLen: Int32
) -> UnsafeMutableRawPointer? {
    guard let metaJSON, let model, modelLen > 0 else { return nil }
    guard let assets = try? ModelAssets(
        metaJSON: String(cString: metaJSON),
        modelBytes: Array(UnsafeBufferPointer(start: model, count: Int(modelLen)))) else { return nil }
    return Unmanaged.passRetained(Handle(Shapes(assets: assets))).toOpaque()
}

/// Create a recognizer from a bundled model **file path** (the Node server-side
/// native, Linux + macOS). `inferenceSession(modelPath:)` inside picks Core ML
/// on Apple hosts (a `.mlmodelc` directory) and LiteRT on Linux (a `.tflite`),
/// so one primitive covers both runtimes. The meta sidecar still crosses as a
/// string; only the model artifact is a path (mmap, no giant copy).
@_cdecl("shapes_create_bundled_path")
public func shapes_create_bundled_path(
    _ metaJSON: UnsafePointer<CChar>?,
    _ modelPath: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let metaJSON, let modelPath else { return nil }
    guard let assets = try? ModelAssets(
        metaJSON: String(cString: metaJSON),
        modelPath: String(cString: modelPath)) else { return nil }
    return Unmanaged.passRetained(Handle(Shapes(assets: assets))).toOpaque()
}

@_cdecl("shapes_destroy")
public func shapes_destroy(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    Unmanaged<Handle>.fromOpaque(handle).release()
}

@_cdecl("shapes_is_downloaded")
public func shapes_is_downloaded(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    (shapes(handle)?.isDownloaded() ?? false) ? 1 : 0
}

/// Download/verify the model ahead of time (blocks). 0 on success, -1 on failure.
@_cdecl("shapes_download")
public func shapes_download(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    guard let shapes = shapes(handle) else { return -1 }
    let ok: Bool = blockingValue {
        do { try await shapes.download(); return true } catch { return false }
    }
    return ok ? 0 : -1
}

@_cdecl("shapes_run")
public func shapes_run(
    _ handle: UnsafeMutableRawPointer?, _ pointBytes: UnsafePointer<UInt8>?,
    _ pointByteLen: Int32, _ minimumConfidence: Double
) -> UnsafeMutablePointer<CChar>? {
    guard let shapes = shapes(handle) else { return nil }
    let points = decodePoints(pointBytes, Int(pointByteLen))
    let options = Options(minimumConfidence: minimumConfidence)
    let payload: [UInt8]? = blockingValue {
        let shape = try? await shapes.recognize(points: points, options: options)
        return encodeShape(shape)
    }
    return payload.flatMap(ffiEmit)
}

@_cdecl("shapes_string_free")
public func shapes_string_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    ffiFree(ptr)
}

// MARK: helpers

/// Decode little-endian f64 pairs (x0,y0,x1,y1,...) into `Point`s.
private func decodePoints(_ ptr: UnsafePointer<UInt8>?, _ byteCount: Int) -> [Point] {
    guard let ptr, byteCount >= 16 else { return [] }
    let count = byteCount / 16
    var points: [Point] = []
    points.reserveCapacity(count)
    for i in 0..<count {
        let base = i * 16
        var xb: UInt64 = 0, yb: UInt64 = 0
        for b in 0..<8 {
            xb |= UInt64(ptr[base + b]) << (8 * b)
            yb |= UInt64(ptr[base + 8 + b]) << (8 * b)
        }
        points.append(Point(x: Double(bitPattern: xb), y: Double(bitPattern: yb)))
    }
    return points
}

/// Encode a recognized shape (or `nil`) as an FFI buffer. Decoded by the Kotlin
/// FfiReader; no JSON hand-rolled either side.
private func encodeShape(_ shape: Shape?) -> [UInt8] {
    var w = FFIWriter()
    guard let shape else {
        w.u32(0)
        return w.bytes
    }
    w.u32(1)
    switch shape {
    case let .line(from, to):
        w.u32(1)
        writePoint(&w, from)
        writePoint(&w, to)
    case let .rectangle(corners):
        w.u32(2)
        writePoints(&w, corners)
    case let .triangle(vertices):
        w.u32(3)
        writePoints(&w, vertices)
    case let .ellipse(center, semiMajor, semiMinor, rotation):
        w.u32(4)
        writePoint(&w, center)
        w.f64(semiMajor)
        w.f64(semiMinor)
        w.f64(rotation)
    case let .star(center, outerRadius, innerRadius, rotation, pointCount):
        w.u32(5)
        writePoint(&w, center)
        w.f64(outerRadius)
        w.f64(innerRadius)
        w.f64(rotation)
        w.u32(pointCount)
    }
    return w.bytes
}

private func writePoint(_ w: inout FFIWriter, _ p: Point) {
    w.f64(p.x)
    w.f64(p.y)
}

private func writePoints(_ w: inout FFIWriter, _ points: [Point]) {
    w.u32(points.count)
    for p in points { writePoint(&w, p) }
}
#endif
