# ShapesAndroidExample

A tiny Android app for trying Shapes with the Maven Central package
`ai.desertant:shapes`.

## Run

Connect a device or start an emulator, then run:

```bash
./gradlew :app:installDebug
```

Draw a single stroke on the canvas and tap Recognize. The first recognition
downloads and caches the model.
