#if os(Android)
import Android
import HostBridge

// JNI entry points for ai.desertant.shapes.ShapesNative, written directly in
// Swift (no C shim). The reusable harness (byte marshalling, thread attach, and
// installing the CHostBridge JSON/HTTP callbacks against the host class) lives
// in desert-ant-core's HostBridge module; this file forwards to the C ABI in
// CABI.swift. The API mirrors the Swift SDK: an instance (opaque handle) per
// Shapes, with lazy loading, isDownloaded, download, and run.
//
// The model is either bundled (createBundled, bytes from shapes-tflite-resources)
// or loaded on demand (create, download/local dir).
// Points cross as a little-endian f64 byte array; the recognized shape comes
// back as the FFIBuffer length-prefixed typed buffer. Handles cross as jlong.

private func handle(_ ptr: UnsafeMutableRawPointer?) -> jlong { jlong(Int(bitPattern: ptr)) }
private func pointer(_ handle: jlong) -> UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: Int(handle)) }

/// Create a recognizer. `cacheRoot` is the app cache dir (base for the managed
/// nested layout); `directory` is an explicit model dir (direct) or NULL/empty
/// for the managed layout under `cacheRoot`.
@_cdecl("Java_ai_desertant_shapes_ShapesNative_create")
public func ShapesNative_create(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?,
                                _ cacheRoot: jbyteArray?, _ directory: jbyteArray?) -> jlong {
    installHostBridge(env, cls)  // wires JSON + http callbacks to ShapesNative's statics
    let root = hostCopyBytes(env, cacheRoot).flatMap { $0.isEmpty ? nil : Array($0) }
    let dir = hostCopyBytes(env, directory).flatMap { $0.isEmpty ? nil : Array($0) }
    return withHostCText(root) { rootPtr in
        withHostCText(dir) { dirPtr in handle(shapes_create(rootPtr, dirPtr)) }
    }
}

/// Create a recognizer from bundled model bytes (the shapes-tflite-resources path).
@_cdecl("Java_ai_desertant_shapes_ShapesNative_createBundled")
public func ShapesNative_createBundled(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?,
                                       _ metaJson: jbyteArray?, _ model: jbyteArray?) -> jlong {
    installHostBridge(env, cls)
    guard let meta = hostCopyBytes(env, metaJson), let mdl = hostCopyBytes(env, model) else { return 0 }
    return withHostCText(meta) { metaC in
        mdl.withUnsafeBufferPointer { m in
            handle(shapes_create_bundled(metaC, m.baseAddress, Int32(m.count)))
        }
    }
}

@_cdecl("Java_ai_desertant_shapes_ShapesNative_destroy")
public func ShapesNative_destroy(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?, _ handle: jlong) {
    shapes_destroy(pointer(handle))
}

@_cdecl("Java_ai_desertant_shapes_ShapesNative_isDownloaded")
public func ShapesNative_isDownloaded(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?, _ handle: jlong) -> jint {
    installHostBridge(env, cls)
    return jint(shapes_is_downloaded(pointer(handle)))
}

/// Download/verify the model ahead of time. Blocking; call off the main thread.
@_cdecl("Java_ai_desertant_shapes_ShapesNative_download")
public func ShapesNative_download(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?, _ handle: jlong) -> jint {
    installHostBridge(env, cls)
    return jint(shapes_download(pointer(handle)))
}

/// Recognize a stroke. `pointBytes` is little-endian f64 pairs (x0,y0,x1,y1,...).
@_cdecl("Java_ai_desertant_shapes_ShapesNative_run")
public func ShapesNative_run(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?,
                             _ handle: jlong, _ pointBytes: jbyteArray?,
                             _ minimumConfidence: jdouble) -> jbyteArray? {
    installHostBridge(env, cls)
    guard let bytes = hostCopyBytes(env, pointBytes) else { return nil }
    let buf = bytes.withUnsafeBufferPointer { p in
        shapes_run(pointer(handle), p.baseAddress, Int32(p.count), minimumConfidence)
    }
    return hostTakeBuffer(env, buf)
}
#endif
