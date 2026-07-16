# Third-party notices - Shapes

The bundled `shapes` model is trained on synthetic and open stroke data under
the licenses below, each permitting commercial use and derivative works.

## Training data (not redistributed here)
- **Quick, Draw!** - Google - **CC-BY-4.0**. Human-drawn stroke samples used as
  one source of training and negative ("none") examples.
  Attribution: **"The Quick, Draw! Dataset, Google"**.
- Synthetic strokes generated procedurally (parametric shapes plus hand-jitter
  augmentation) in the private `shapes-training` repository.

No non-commercial or unlicensed data is used.

## Android platform libraries

Android JSON parsing uses the Kotlin host's native JSON through the JNI host,
and on-demand model download uses the host's HTTP stack. On-device inference
uses LiteRT (`libLiteRt.so`). No JSON or HTTP library is vendored or
hand-rolled in the native layer.
