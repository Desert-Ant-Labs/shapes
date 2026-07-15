# ShapesWasmExample

Node and headless-browser examples for `@desert-ant-labs/shapes`.

```bash
npm install
npm run node-example      # onnxruntime-node
npm run browser-example   # headless Chromium + onnxruntime-web (needs playwright)
```

Both recognize a wobbly hand-drawn rectangle. The first run downloads and caches
the model.
