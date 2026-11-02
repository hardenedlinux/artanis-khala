# Khala

Khala is a GNU Artanis application that aims for practical compatibility with
the ComfyUI ecosystem. This initial implementation defines a focused node
registry and workflow validation for text-to-image graphs; it is not a full
ComfyUI replacement.

## Development

1. Install GNU Guile 3.0 and GNU Artanis.
2. Set options in [`conf/khala.conf`](conf/khala.conf); see
   [configuration](docs/usage/configuration.md).
3. Fetch the pinned official frontend with `./tools/fetch-frontend.scm`.
4. Start the app with `art work` from this directory.

The default engine is `fake`, intended for protocol development. The optional
SonicBoom adapter is lazy loaded and remains untested. The application uses
Artanis's SQLite3 backend for local persistence.
