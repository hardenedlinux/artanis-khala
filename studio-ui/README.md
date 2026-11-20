# Khala Studio UI

Standalone React frontend for the existing Khala Artanis Studio backend.
It is deliberately isolated from `ui/`: it does not change `/`, `/khala`,
ComfyUI-compatible endpoints, or the existing Khala UI build.

## Build

```sh
cd studio-ui
npm install
npm run build
```

Build output:

```text
dist/
  index.html
  studio-ui.js
  studio-ui.css
  vendor/
    react.production.min.js
    react-dom.production.min.js
```

The app bundle is a classic script and can be loaded by a blank HTML shell.
React 18.3.1 and ReactDOM 18.3.1 are copied from the local npm installation;
there are no runtime CDN requests.

## Artanis integration

`GET /studio` and `GET /studio/index.html` serve the blank React mount shell in
`app/views/studio/studio.html.tpl`. The Studio controller exposes only these
exact built files:

- `/studio/assets/studio-ui` -> `studio-ui/dist/studio-ui.js`
- `/studio/assets/studio-ui-theme` -> `studio-ui/dist/studio-ui.css`
- `/studio/assets/react` -> `studio-ui/dist/vendor/react.production.min.js`
- `/studio/assets/react-dom` -> `studio-ui/dist/vendor/react-dom.production.min.js`

Only serve this allowlist. Do not accept arbitrary file paths from URL parameters.
The public URLs intentionally have no `.js` or `.css` suffix because Artanis
reserves those suffixes for its global `pub/` static handler.

Build `studio-ui/dist/` before starting Artanis. The generated `dist/` directory
is intentionally ignored by Git, matching the existing `ui/dist/` workflow.
A route sketch is provided in `integration/ARTANIS-INTEGRATION.md`, with a Scheme snippet in `integration/studio-controller-routes.scm.txt`.

## Backend API contract

The UI calls the actual v1 endpoints under `/studio/api/v1` and unwraps
`{ "data": ... }` responses. It handles `{ "error": { "code", "message",
"current_revision" } }` errors and the `meta`, `token`, `done`, `error` SSE
stream used by the current Continue endpoint.

Implemented against the API visible in the current master branch:

- GET/POST/GET/PUT Workplace
- GET/POST/GET/PUT Documents
- GET/POST/GET/restore Versions
- POST Inspire
- POST Continue (SSE)
- GET Capabilities

The current backend does not expose persisted Character, Scene, Asset or
Studio Settings endpoints. Those navigation destinations are present as
clearly marked design placeholders, not fake CRUD. Model preference and
editor presentation preferences are stored in this browser only until a
backend settings endpoint is introduced.

## Design constraints

- Solid colors only. No gradients, neon, glow, or cyberpunk styling.
- Leather-bound book covers and an editorial double-page writing surface.
- Opening and closing a Workplace are brand rituals; no skip/disable toggle.
- Read/write mode, page-turn animation, inspiration and explicit AI continuation.
- AI output remains a candidate until the author accepts it.

## Important implementation note

The backend stores one continuous Markdown document. The UI paginates that
content for display only. Page numbers and page boundaries are never sent to
the backend.


## Build verification

The bundle has been built with the local Node/npm installation, and
`node --check dist/studio-ui.js` passes. `npm run build` copies React and
ReactDOM 18.3.1 into `dist/vendor/`; the browser makes no CDN requests.
