# Khala Studio API v1

Khala Studio is the writing prototype served at `/studio`. Its backend API is
local to the Artanis process and is mounted under:

```text
/studio/api/v1
```

The backend stores writing data in its own SQLite database. It does not reuse
ComfyUI history or queue persistence.

## Configuration

`conf/khala.conf` and the defaults in `lib/khala/config.scm` include:

```text
studio_db = var/studio.sqlite3
studio_model =
```

- `studio_db` is the Studio SQLite path. Missing parent directories are created.
- `studio_model` optionally selects the default writing model. If it is empty,
  the first installed LLM is used; the fake engine falls back to the built-in
  `fake` model.
- The existing `engine` setting selects the adapter. Supported values are
  `fake` and `sonicboom`; Studio does not introduce another inference backend.

The database is initialized on first use and runs migrations through version
`3`. The schema includes:

- `studio_schema_migrations`
- `studio_workplaces`
- `studio_documents`
- `studio_document_versions`
- `studio_characters`
- `studio_scenes`
- `studio_scene_cast`

`studio_characters` stores a stable UUID, `workplace_id`, `name`, `role`,
`summary`, four independent JSON identity objects, timestamps, and a nullable
`archived_at` soft-delete marker.

All mutations use SQLite transactions and parameterized SQL. Foreign keys and a
five-second busy timeout are enabled for every connection.

## Response Envelope

Successful responses:

```json
{"data": {}}
```

Errors:

```json
{"error":{"code":"ERROR_CODE","message":"Human-readable message"}}
```

Revision conflicts additionally include the latest revision:

```json
{"error":{"code":"REVISION_CONFLICT","message":"Document revision changed","current_revision":4}}
```

IDs are UUID strings. Timestamps are ISO 8601 UTC strings. Request bodies are
limited to 4 MiB and document content to 2,000,000 characters.

## Capabilities

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/capabilities
```

The model list comes from the existing installed LLM files. Under the fake
engine, a usable `fake` model is also exposed.

## Workplaces

List non-archived Workplaces ordered by last activity:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces
```

Create a Workplace:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces \
  -H 'Content-Type: application/json' \
  -d '{"title":"My Creative World","description":"A short description","cover_color":"#713D3B"}'
```

Read Workplace metadata. Opening a Workplace updates `last_opened_at`:

```sh
WORKPLACE_ID=00000000-0000-4000-8000-000000000000
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID
```

Update metadata:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID \
  -H 'Content-Type: application/json' \
  -d '{"title":"Velvet Moon","description":"Draft one","cover_color":"#354B40","cover_asset_id":null}'
```

`cover_color` must be a `#RRGGBB` value. `cover_asset_id` accepts a UUID or
`null`; arbitrary filesystem paths are rejected.

## Characters

Characters are first-class Workplace resources with a stable UUID. They are
not documents and can therefore be referenced by future Scenes, Assets and
Productions without duplicating identity data.

List non-archived characters:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters
```

Create a character. Identity sections are independent JSON objects; omitted
sections start empty:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"Mara Vale",
    "role":"Protagonist",
    "summary":"A cartographer returning to the coast.",
    "literary_identity":{
      "background":"Raised beside the northern harbor.",
      "personality":"Observant and guarded.",
      "values":"Loyalty to place.",
      "motivations":"Find the drowned district.",
      "fears":"Being lost at sea.",
      "goals":"Complete the map.",
      "arc":"From guarded exile to chosen belonging."
    },
    "visual_identity":{
      "standard_appearance":"Tall, weathered blue coat.",
      "face":"Sharp features and salt-burned skin.",
      "body":"Lean and weather-hardened.",
      "hair":"Dark, cut short.",
      "clothing":"Blue harbor coat, brass compass.",
      "palette":"Sea blue, brass, wet stone.",
      "expressions":"Still eyes; rare, brief smile.",
      "posture":"Square shoulders, hands never fully at rest."
    },
    "vocal_identity":{
      "timbre":"Low and dry.",
      "range":"Narrow, controlled.",
      "pitch":"Slightly below average.",
      "accent":"Northern harbor.",
      "pronunciation":"Swallows final consonants.",
      "pace":"Measured with long pauses."
    },
    "performance_identity":{
      "habits":"Taps the table twice before speaking.",
      "movement":"Deliberate, economical.",
      "gestures":"Turns the compass when thinking.",
      "emotional_responses":"Goes quiet when challenged.",
      "situations":"Formal under authority; unguarded only near water."
    }
  }'
```

Read a full character:

```sh
CHARACTER_ID=00000000-0000-4000-8000-000000000003
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID
```

Update one identity section without touching the other three. Keys not present
in the request are left unchanged. Unknown identity fields return HTTP `400`:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID \
  -H 'Content-Type: application/json' \
  -d '{"visual_identity":{"clothing":"Blue harbor coat with a repaired sleeve."}}'
```

Archive a character with a soft delete:

```sh
curl --noproxy '*' -X DELETE http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID
```

Archived characters disappear from list and detail responses, while the row
and stable UUID remain in `studio_characters` for future references. Every
nested character request verifies that both the Workplace and Character exist
and belong together.

The visual identity is author-controlled Canon. This API has no generation
path that can modify it; future AI suggestions must be approved by the author
before being written through this `PUT` endpoint.

## Scenes and Casting

A Scene is a staged dramatic situation, not another document. Its structured
fields stay separate from Writing and from the persistent Character identity.
`given_circumstances`, `dramatic_situation`, and `direction` are nested objects
in the API; SQLite stores them in explicit columns in `studio_scenes`.

List non-deleted Scenes ordered by `sort_order`:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes
```

Create a Scene:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes \
  -H 'Content-Type: application/json' \
  -d '{
    "title":"The Drowned District",
    "summary":"A confrontation at the tide line.",
    "sort_order":1,
    "status":"draft",
    "given_circumstances":{
      "time":"Before dawn",
      "place":"The northern harbor",
      "environment":"Fog and low tide",
      "background":"The district was abandoned ten years ago.",
      "prior_events":"Mara found the old survey map."
    },
    "dramatic_situation":{
      "central_question":"Will Mara admit why she returned?",
      "primary_conflict":"Mara wants the truth; Ilyan wants her gone.",
      "turn":"Ilyan reveals the lighthouse was never abandoned."
    },
    "dialogue":"MARA\nYou came back.",
    "direction":{
      "blocking":"Mara stays between Ilyan and the stairs.",
      "spatial":"A narrow pier above black water.",
      "performance_direction":"Speak quietly.",
      "camera":"Hold on the survey map."
    }
  }'
```

`status` is one of `draft`, `ready`, or `final`. Scene text fields are limited
to 500,000 characters each. Unknown fields inside the nested objects return
HTTP `400`.

Read a Scene:

```sh
SCENE_ID=00000000-0000-4000-8000-000000000004
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID
```

Update Scene fields. A nested object may be partial; omitted fields keep their
current values:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID \
  -H 'Content-Type: application/json' \
  -d '{"status":"ready","dramatic_situation":{"turn":"The lamp is still warm."},"direction":{"camera":"Slow push toward the stair."}}'
```

Archive a Scene with a soft delete. Its Character rows and Cast relationship
rows are not deleted:

```sh
curl --noproxy '*' -X DELETE http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID
```

### Scene Cast

Cast entries reference an existing Character UUID. The same Character may
appear in many Scenes, with different objectives and behaviour in each one.
Objective, Action, Conflict, Emotional State, Performance Direction, and
Subtext belong to the Scene Cast entry and never overwrite Character identity.

Read the cast, including stable Character IDs and current Character names:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/cast
```

Replace the entire cast in one transaction:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/cast \
  -H 'Content-Type: application/json' \
  -d '{
    "cast":[
      {
        "character_id":"00000000-0000-4000-8000-000000000003",
        "objective":"Make Ilyan admit he lied.",
        "action":"Ask a question he cannot answer.",
        "conflict":"Ilyan refuses to look at the map.",
        "emotional_state":"Controlled anger.",
        "performance_direction":"Do not raise her voice.",
        "subtext":"She already knows.",
        "sort_order":0
      }
    ]
  }'
```

Every referenced Character must be non-archived and belong to the same
Workplace. A cross-Workplace or unknown Character returns HTTP `422` with
`INVALID_CAST_CHARACTER`. Duplicate Characters in one cast return HTTP `400`.
The update deletes and recreates cast rows inside `BEGIN IMMEDIATE`; if any
validation or insert fails, the previous cast remains intact.

## Documents

List the document tree as a flat, ordered list with `parent_id` relationships.
List entries omit `content` but include `word_count`:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents
```

Create a document:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents \
  -H 'Content-Type: application/json' \
  -d '{"parent_id":null,"kind":"chapter","title":"Chapter 1","content_format":"markdown","content":"","sort_order":1}'
```

Supported kinds are `manuscript`, `chapter`, `outline`, and `note`. A parent
must exist in the same Workplace. `content_format` must be `markdown`.

Read a full document:

```sh
DOCUMENT_ID=00000000-0000-4000-8000-000000000001
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID
```

Save continuous Markdown content with optimistic concurrency:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID \
  -H 'Content-Type: application/json' \
  -d '{"title":"Chapter 1","content":"The full continuous Markdown document...","content_format":"markdown","expected_revision":3}'
```

`expected_revision` is mandatory. A stale value returns HTTP `409` and never
overwrites the newer content. If title, content, and format are unchanged, the
revision is not incremented. Autosave does not create a version snapshot.

The API stores one continuous document per record. Page boundaries are a
frontend layout concern and are never inserted into the stored Markdown.

## Version History

List version metadata, newest first. The list does not include historical
content:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/versions
```

Create an immutable checkpoint:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/versions \
  -H 'Content-Type: application/json' \
  -d '{"label":"Before major revision","source":"checkpoint"}'
```

`source` is one of `manual`, `ai`, `restore`, or `checkpoint`.

Read a version, including content:

```sh
VERSION_ID=00000000-0000-4000-8000-000000000002
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/versions/$VERSION_ID
```

Restore a version:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/versions/$VERSION_ID/restore \
  -H 'Content-Type: application/json' -d '{}'
```

Restore increments the current document revision and records a new `restore`
audit snapshot. The selected historical row is never modified or deleted.

## Inspire

Generate creative directions without changing the source document:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/ai/inspire \
  -H 'Content-Type: application/json' \
  -d '{"model":"fake","selected_text":"The selected passage","context_before":"Text before","context_after":"Text after","instruction":"Give me several ways to develop this scene."}'
```

Response:

```json
{"data":{"content":"Markdown-formatted creative suggestions...","model":"fake"}}
```

The system prompt lives in `conf/studio-prompts/inspire.md`. The result is
inspiration only and is never written to the document.

## Continue Writing (SSE)

Stream a candidate continuation:

```sh
curl --noproxy '*' -N -X POST \
  http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/ai/continue \
  -H 'Content-Type: application/json' \
  -d '{"model":"fake","selected_text":"","context_before":"The text preceding the cursor...","context_after":"","instruction":"Continue this scene with restrained emotional tension.","max_tokens":1024}'
```

Events:

```text
event: meta
data: {"run_id":"uuid","model":"fake"}

event: token
data: {"text":"The next generated text"}

event: done
data: {"run_id":"uuid","finish_reason":"stop"}
```

If generation fails after streaming starts:

```text
event: error
data: {"code":"GENERATION_FAILED","message":"Generation failed"}
```

The response uses `text/event-stream`, `Cache-Control: no-cache`, and
`X-Accel-Buffering: no`. The existing engine `on-token` callback emits tokens;
the Artanis stream close hook sets the engine cancellation flag. Generated text
is not saved automatically. The frontend inserts it only after the author
accepts it, then saves with the normal document `PUT`.

The continuation prompt lives in `conf/studio-prompts/continue.md`.

## Status Codes

| Status | Meaning |
|---:|---|
| `200` | Success. |
| `201` | Workplace, character, document, or version created. |
| `400` | Invalid JSON, UUID, enum, string, or numeric input. |
| `404` | Workplace, character, document, or version not found. |
| `409` | `REVISION_CONFLICT`; the response includes `current_revision`. |
| `413` | Request body exceeds 4 MiB. |
| `422` | Invalid resource state, such as a parent from another Workplace. |
| `502` | Generation failed. |
| `503` | Inference engine or model unavailable. |

When SonicBoom is configured but unavailable, Studio returns a clear `503`
without attempting to load another inference subsystem. The fake engine needs
no models or GPU and is suitable for tests.

## Frontend

Open the prototype at:

```text
http://127.0.0.1:3000/studio
```

The React bundle in `studio-ui/` loads Workplaces, documents and Characters from
this API. The Characters workspace creates and edits the four identity sections
independently, persists them to SQLite, and archives characters with a soft
delete. Writing continues to autosave with `expected_revision`, request
inspiration, consume continuation SSE, and insert accepted text only after the
author approves it.

## Tests

Run the persistence and HTTP integration suite with the fake engine:

```sh
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$PWD/lib:$PWD" guile test/studio/persistence.scm
./test/studio/run.sh
```

The runner creates temporary SQLite files, starts and stops Artanis twice, and
checks persistence across a restart. It never enables SonicBoom.
