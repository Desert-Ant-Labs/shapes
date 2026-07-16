# ShapesWasmExample

Node and headless-browser examples for `@desert-ant-labs/shapes`.

```bash
npm install
npm run node-example      # API-shape smoke test (LiteRT.js is browser-only)
npm run browser-example   # headless Chromium + LiteRT.js (needs playwright)
```

The browser example recognizes a wobbly hand-drawn rectangle on device via
LiteRT.js. LiteRT.js needs a DOM, so the Node example only exercises the API
shape and the graceful "runtime absent" path. The first run downloads and
caches the model.
