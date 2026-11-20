# Artanis integration notes

The current `app/controllers/studio.scm` serves
`app/views/studio/studio.html.tpl` for `/studio` and `/studio/index.html`. That
view matches `studio-ui/integration/studio-view.html`.

Add an explicit asset allowlist in the Studio controller (or a small separate
controller). The route should resolve only the four known built files below,
not concatenate an arbitrary request path onto a filesystem root.

| URL | File |
|---|---|
| `/studio/assets/studio-ui` | `studio-ui/dist/studio-ui.js` |
| `/studio/assets/studio-ui-theme` | `studio-ui/dist/studio-ui.css` |
| `/studio/assets/react` | `studio-ui/dist/vendor/react.production.min.js` |
| `/studio/assets/react-dom` | `studio-ui/dist/vendor/react-dom.production.min.js` |

Use the correct content types: `text/javascript` for JS and `text/css` for CSS.
Set long-lived cache headers for versioned deployment assets, or use `no-cache`
while the filenames remain stable during development.

The public paths deliberately omit `.js`/`.css` suffixes. Artanis registers a
global route for those extensions against `pub/`, which would otherwise race
with exact controller routes.

Do not alter `/`, `/khala`, `/khala/api/*`, ComfyUI, or Ollama/OpenAI routes.
