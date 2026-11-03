# Khala UI

Build the React UI:

```sh
cd ui
npm ci
npm run build
```

Or run `tools/build-ui.sh`. Artanis serves the build at `/khala/`; the
ComfyUI-compatible node editor remains at `/`.

For development run `npm run dev` in `ui/`. Vite serves `/khala/` and proxies
Khala's API, WebSocket, image, upload, prompt and history routes to port 3130.
