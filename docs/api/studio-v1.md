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
studio_assets_dir = var/studio-assets
studio_asset_max_bytes = 4194304
studio_model =
```

- `studio_db` is the Studio SQLite path. Missing parent directories are created.
- `studio_assets_dir` is the server-managed root for Asset file bytes. It is
  independent from ComfyUI input, output, history, and queue storage.
- `studio_asset_max_bytes` limits each uploaded Asset to 4 MiB, leaving room
  for multipart framing inside the Artanis 5 MiB request limit.
- `studio_model` optionally selects the default writing model. If it is empty,
  the first installed LLM is used; the fake engine falls back to the built-in
  `fake` model.
- The existing `engine` setting selects the adapter. Supported values are
  `fake` and `sonicboom`; Studio does not introduce another inference backend.

The database is initialized on first use and runs migrations through version
`7`. The schema includes:

- `studio_schema_migrations`
- `studio_workplaces`
- `studio_documents`
- `studio_document_versions`
- `studio_characters`
- `studio_character_identity_drafts`
- `studio_character_outfits`
- `studio_scenes`
- `studio_scene_cast`
- `studio_assets`
- `studio_asset_tags`
- `studio_asset_links`

`studio_characters` stores a stable UUID, `workplace_id`, `name`, `role`,
`summary`, the original `concept`, four independent JSON identity objects,
author-approved `avatar_asset_id` and `full_body_asset_id` references,
timestamps, and a nullable `archived_at` soft-delete marker. Identity drafts
are held in a physically separate table so an AI proposal cannot become Canon
without an explicit apply request. Outfits are character-owned rows with JSON
string arrays for components, materials, colours, accessories and special
features.

`studio_scenes` stores the structured dramatic fields plus a `storyboard` JSON
column. Migration `5` adds this column. Migration `7` adds
`reference_asset_ids`, an ordered JSON array of author-approved Scene reference
image Asset IDs. Storyboards remain owned by the Scene; they are not a separate
document or workflow subsystem.

`studio_assets` stores Asset metadata and a server-generated `storage_key`, but
never stores a client-supplied filesystem path. File bytes live beneath
`studio_assets_dir`. `studio_asset_tags` stores normalized tags and
`studio_asset_links` stores generic references to `character`, `scene`, or
`document` resources by stable UUID.

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
engine, a usable `fake` model is also exposed. The `image_generation` object
reports the current image adapter, availability, reference-image support and
reference mode. It does not introduce a second model or engine catalogue.

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

### Character Studio

Character Studio extends the existing Character resource. A character may be
created from a natural-language concept; AI output is stored in
`studio_character_identity_drafts`, never directly in the Character row.
Only an explicit draft apply writes an identity section to Canon.

Create a concept-first Character:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"Sera Voss",
    "role":"Mechanic",
    "concept":"一个生活在蒸汽朋克世界的年轻机械师，性格独立，不喜欢依赖别人。"
  }'
```

Generate drafts for all four identity sections. Non-empty Canon fields are
locked: the model may fill gaps but the server removes any value aimed at a
locked field. `format` is not used; the response is strictly parsed as JSON.

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/ai/develop \
  -H 'Content-Type: application/json' \
  -d '{"concept":"一个生活在蒸汽朋克世界的年轻机械师，性格独立，不喜欢依赖别人。"}'
```

Regenerate one section:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/ai/develop/visual_identity \
  -H 'Content-Type: application/json' \
  -d '{"instruction":"让服装更适合工坊，但不要改变已经确认的脸。"}'
```

If a draft was edited by the author, regeneration returns HTTP `409` with
`DRAFT_PROTECTED` unless the request explicitly includes `"force":true`.

List and edit drafts:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/ai/drafts

curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/ai/drafts/visual_identity \
  -H 'Content-Type: application/json' \
  -d '{"content":{"face":"作者修改后的脸部 Canon。","hair":"深色短发，用黑色绳带束起。"}}'
```

Apply a draft to Canon, or discard it:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/ai/drafts/visual_identity/apply

curl --noproxy '*' -X DELETE http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/ai/drafts/vocal_identity
```

Outfits are independent Character resources. The first Outfit becomes the
default automatically; choosing another default clears the previous one in
the same transaction.

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"Standard Outfit",
    "kind":"standard",
    "description":"工坊里的标准工作装。",
    "components":["long charcoal coat","reinforced trousers","leather apron"],
    "materials":["waxed canvas","leather","brass"],
    "colors":["charcoal","oxblood","aged brass"],
    "accessories":["brass thumb guard"],
    "special_features":["reinforced left sleeve"],
    "image_prompt":"Practical steampunk workwear, visible repairs, no decorative glow."
  }'

curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits/$OUTFIT_ID
```

Update, archive or select the default Outfit:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits/$OUTFIT_ID \
  -H 'Content-Type: application/json' \
  -d '{"description":"工坊标准装，左袖有加厚护片。"}'

curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits/$OUTFIT_ID/default

curl --noproxy '*' -X DELETE http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits/$OUTFIT_ID
```

Archiving is a soft delete. If the archived Outfit was the default, the next
active Outfit becomes default. Character identity is never changed by Outfit
updates.

#### Character Artwork

Artwork Prompt composition uses the approved Visual Identity, the selected
Outfit, the composition requirements for the artwork type and optional author
direction. Supported types are `avatar`, `full_body`, `character_sheet`,
`expression_sheet` and `outfit`. The composed prompt is returned for review and
editing before generation:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/artworks/prompt \
  -H 'Content-Type: application/json' \
  -d '{"artwork_type":"full_body","outfit_id":"'"$OUTFIT_ID"'","extra_description":"站在工坊窗边，午后侧光。"}'
```

Generate one still image. The existing `engine-run-t2i` adapter is used through
`comfy-render-image!`; this endpoint does not introduce another image engine.
The finished PNG is stored in the existing Asset library, linked to the
Character, and annotated in `generation_metadata` with artwork type, Character
ID, Outfit ID, model information and the final prompt:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/artworks/generate \
  -H 'Content-Type: application/json' \
  -d '{"artwork_type":"full_body","outfit_id":"'"$OUTFIT_ID"'","prompt":"<edited prompt>"}'
```

List Character artwork Assets:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/artworks
```

Generation never overwrites an older Asset and never writes Character Canon.
Repeated generation creates a new Asset.

Approve an image as the formal Avatar, the formal Full Body reference, or as an
Outfit reference image:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/avatar \
  -H 'Content-Type: application/json' \
  -d '{"asset_id":"'"$ASSET_ID"'"}'

curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/full-body \
  -H 'Content-Type: application/json' \
  -d '{"asset_id":"'"$ASSET_ID"'"}'

curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/outfits/$OUTFIT_ID/reference \
  -H 'Content-Type: application/json' \
  -d '{"asset_id":"'"$ASSET_ID"'"}'
```

All three endpoints require an image Asset from the same Workplace that is
already linked to this Character. Cross-Workplace Assets return `404`/`422`.
The full-body approval is separate from the Avatar: Storyboard reference
selection prefers an approved full body and falls back to the approved Avatar.

Read the consolidated author-approved Canon view:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/canon
```

It returns the Character identity, approved Avatar and Full Body Assets, active
Outfits and any pending AI drafts. Drafts are explicitly not Canon.

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

### Scene References

Author-approved Scene reference images are stored as an ordered set of Asset
IDs. Every ID must identify an image Asset in the same Workplace that is
already linked to this Scene; otherwise the API returns `422`
`INVALID_ASSET` or `ASSET_NOT_LINKED`. Duplicate IDs and more than 12 images
are rejected. Passing an empty array clears the approval set without deleting
any Asset.

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/references \
  -H 'Content-Type: application/json' \
  -d '{"asset_ids":["'"$ASSET_ID"'"]}'
```

The Scene response includes `reference_asset_ids` and `reference_count`.
Generating a Storyboard image collects only IDs approved here; other images
merely linked to the Scene remain available as Assets but are not silently
treated as references.

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

## Storyboard and Visual Output

A Storyboard belongs to one Scene. Creating it collects the Scene's Given
Circumstances, Dramatic Situation, Cast objectives/actions/conflicts/emotional
states/subtext, each Character's Literary, Visual and Performance Identity, and
the text metadata of linked Scene/Character Assets. The author does not re-enter
information already stored in those resources.

With the configured `sonicboom` text engine, the Storyboard prompt in
`conf/studio-prompts/storyboard.md` asks the existing `engine-chat` adapter to
choose the shot count and dramatic progression from the Scene. Its reply must
be one JSON object with exactly a `shots` array; every shot must contain exactly
`dramatic_beat`, `action`, `character_ids`, `expression`, `performance`,
`camera`, `visual_description`, and `image_prompt`. The server validates the
whole schema before saving. Invalid JSON, missing/extra fields, unknown
Character IDs, duplicate cast entries, an empty board, or more than eight shots
return HTTP `502` `INVALID_STORYBOARD_OUTPUT`; the existing Storyboard is left
untouched. Character IDs must come from the current Scene Cast. The server
derives Character names and appends an authoritative Visual Canon block to
every image prompt, so the model cannot silently replace permanent appearance.

With `engine = fake`, creation keeps the deterministic four-shot template used
by tests and demos. This is also the fallback used by the test suite, which
never starts SonicBoom. Asset text metadata is supplied to the model, but no
pixel-level visual understanding is claimed or available.

Read the Storyboard:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/storyboard
```

Create the initial shots. Calling it again returns the saved Board unless
`{"force":true}` is supplied. An optional `model` overrides the configured
Studio writing model; optional `max_tokens` is limited to 4096:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/storyboard \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen-model","max_tokens":2048}'
```

Regeneration is never implicit. If any current shot is author-edited,
image-generated, or comes from a legacy board without authorship tracking, a
forced replacement without acknowledgement returns HTTP `422`
`STORYBOARD_PROTECTED` and does not write. After the author explicitly confirms
replacement, send:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/storyboard \
  -H 'Content-Type: application/json' \
  -d '{"force":true,"acknowledge_protected":true}'
```

Replacing the Board never deletes previous image Assets. Only after the author
explicitly invokes an image-generation action does a shot enter that flow.

Save edited shots atomically. The server accepts the structured fields
`dramatic_beat`, `action`, `expression`, `performance`, `camera`,
`visual_description`, and `image_prompt`. `content` remains an alias for
`action`, and `expression_action` remains a compatibility field. The server
ignores client-provided derived Asset state and preserves the existing
`asset_id`, `file_url`, and status for each known shot ID. Once an editable
field changes, the shot is marked `author_edited = true`; saving an unchanged
shot does not create that marker:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/storyboard \
  -H 'Content-Type: application/json' \
  -d '{"shots":[{"id":"00000000-0000-4000-8000-000000000010","number":1,"dramatic_beat":"Mara crosses the threshold into the place she left.","action":"Mara steps into the drowned district.","character_ids":["00000000-0000-4000-8000-000000000003"],"expression":"Guarded recognition.","performance":"She pauses before the second step and keeps one hand on the map.","camera":"Wide 24mm establishing shot.","visual_description":"Fog, wet stone, sea-blue coat.","image_prompt":"Cinematic 16:9 storyboard frame..."}]}'
```

Shot responses also include `source` (`ai`, `deterministic`, or `manual`) and the
`model` that produced an AI draft. AI output is only a draft; the author can
edit and save every shot before choosing to generate an image.

Each shot may also carry `character_outfits`, an array of
`{"character_id":"...","outfit_id":"..."}` entries selecting one Outfit per
Character in that shot. Both IDs must belong to the Scene Cast and the same
Workplace. The selection is Scene/Shot context: it changes the costume used for
that image without modifying the Character's Visual Canon or default Outfit.

Generate an image for one shot:

```sh
curl --noproxy '*' -X POST \
  http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/storyboard/shots/$SHOT_ID/image
```

The response includes the updated shot and its new Asset. Generated image bytes
are stored in `studio_assets_dir`, the Asset is created with
`source = "generated"`, and it is linked to the current Scene. Regenerating a
shot creates a new Asset; the previous Asset is not overwritten. The source
Scene and Dialogue are never changed by generation.

Before rendering, the server collects only author-approved references:

- the Character's approved Full Body Asset, falling back to the approved
  Avatar;
- the approved reference image of the Outfit selected for that Character in
  the Shot;
- the image Assets explicitly approved through the Scene's
  `reference_asset_ids` endpoint.

Unapproved Draft artwork and images that are merely linked to a Scene are not
used. Every reference is tied to its Character, Outfit, or Scene Asset ID. The
shot and its Asset metadata include `reference_usage` with the engine, mode,
`applied` flag, message, and traceable reference metadata plus a safe
`file_url`. The binary file bytes are passed to the adapter only when the
adapter declares reference-image support.

`GET /studio/api/v1/capabilities` exposes
`image_generation.reference_images`, `reference_mode`, and
`max_references`. The current SonicBoom/MOSS-Image binding is text-to-image
only (`reference_images = false`); it does not accept an init image, reference
image, or a reference list. In that configuration approved references are
still collected and reported, but the server preserves the text-to-image path
and never claims that pixels were used. The fake adapter in tests accepts real
bytevectors and declares `reference_mode = "fake-byte-buffer"` so the plumbing
can be verified without a GPU.

The endpoint runs synchronously through the same `engine-run-t2i` adapter used
by the ComfyUI worker, without submitting a queue item or starting a worker.
With `engine = fake`, a deterministic PNG is returned for demos and tests.
If the configured image service is unavailable the API returns `503`
`IMAGE_SERVICE_UNAVAILABLE`; a failed generation returns `502`
`GENERATION_FAILED` and leaves the Storyboard and Scene intact. There is no
fabricated success image.

## Assets

Assets form the Workplace's shared creative library. File bytes and metadata
are stored separately: SQLite holds the Asset record, tags, checksum, and a
server-generated `storage_key`; the file lives under the configured
`studio_assets_dir`. An Asset may be linked to any number of Characters,
Scenes, and Documents, and each of those resources may use many Assets.

Supported `asset_type` values are `image`, `audio`, `video`, `document`, and
`other`. Supported `source` values for metadata-only creation are `generated`
and `imported`; multipart uploads always record `source` as `upload`.

List non-archived Assets ordered by recent activity:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets
```

Create a metadata-only Asset entry:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"Research notes index",
    "description":"References gathered for the harbor sequence.",
    "asset_type":"document",
    "source":"imported",
    "author":"Studio author",
    "notes":"Metadata-only entry.",
    "tags":["research","harbor"],
    "generation_metadata":{"workflow":"manual-reference"}
  }'
```

Clients cannot set `storage_key`, `checksum`, or `file_size`; those fields are
server-managed and return HTTP `400` if supplied. `generation_metadata` is a
forward-compatible JSON object for generated-source metadata such as model,
task ID, or parameters.

Upload a file with `multipart/form-data` using the field name `file`:

```sh
curl --noproxy '*' -X POST \
  http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/upload \
  -F 'file=@portrait.png;type=image/png' \
  -F 'name=Mara Portrait' \
  -F 'description=Approved visual reference' \
  -F 'asset_type=image' \
  -F 'author=Studio author' \
  -F 'tags=["mara","portrait"]' \
  -F 'generation_metadata={"workflow":"manual-reference"}'
```

The server derives the final storage filename, validates the extension, MIME
type, magic bytes or UTF-8 text, file size, and requested `asset_type`, then
writes through a temporary file before renaming it into place. A checksum is
recorded as lowercase SHA-256. The database row is created only after the file
is safely stored; if the insert fails, the new file is removed.

Upload failures use HTTP `400`, or `413` for an Asset over
`studio_asset_max_bytes`, with codes such
as `INVALID_UPLOAD`, `INVALID_FILENAME`, `MIME_MISMATCH`, `INVALID_CONTENT`,
`UNSUPPORTED_MEDIA_TYPE`, `TYPE_MISMATCH`, and `FILE_TOO_LARGE`. HTML, SVG,
script, executable, and other dangerous types are rejected.

Read Asset metadata. Detail responses include current links:

```sh
ASSET_ID=00000000-0000-4000-8000-000000000005
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID
```

Update editable metadata. Omitted fields stay unchanged:

```sh
curl --noproxy '*' -X PUT http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID \
  -H 'Content-Type: application/json' \
  -d '{"name":"Mara Portrait — Canon","description":"Approved visual Canon.","tags":["canon","portrait"],"width":1024,"height":1024}'
```

Use the returned `file_url` to preview the managed file. The endpoint checks the
Asset, Workplace, and canonical storage path; it never accepts a filesystem
path from the client:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID/file
```

Responses include the stored MIME type, inline `Content-Disposition`,
`X-Content-Type-Options: nosniff`, and private caching. A missing file returns
HTTP `404` with `ASSET_FILE_MISSING`.

Archive an Asset with a soft delete. Its links are removed and its managed file
is deleted, while the metadata row retains the stable Asset ID and
`archived_at`:

```sh
curl --noproxy '*' -X DELETE http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID
```

### Asset Links

List an Asset's current links:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID/links
```

Link an Asset to a Character, Scene, or Document:

```sh
curl --noproxy '*' -X POST http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID/links \
  -H 'Content-Type: application/json' \
  -d '{"resource_type":"character","resource_id":"00000000-0000-4000-8000-000000000003"}'
```

`resource_type` is `character`, `scene`, or `document`. The target must exist in
the same non-archived Workplace; otherwise the request returns HTTP `422` with
`INVALID_RESOURCE`. Links store only the resource type and stable UUID, never a
copy of Character or Scene data.

Remove one link:

```sh
curl --noproxy '*' -X DELETE \
  http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/assets/$ASSET_ID/links/character/$CHARACTER_ID
```

Read the Assets attached to a resource:

```sh
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/characters/$CHARACTER_ID/assets
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/scenes/$SCENE_ID/assets
curl --noproxy '*' http://127.0.0.1:3000/studio/api/v1/workplaces/$WORKPLACE_ID/documents/$DOCUMENT_ID/assets
```

Archiving a Character, deleting a Scene, or archiving an Asset also removes the
corresponding link rows in the same transaction. Scene deletion never deletes
Characters or Assets. If an Asset's managed file is missing or unreadable, its
file route returns HTTP `404` with `ASSET_FILE_MISSING` while the metadata row
remains available for repair or deletion.

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
| `201` | Workplace, Character, Outfit, Artwork Asset, Scene, Asset, link, document, or version created. |
| `400` | Invalid JSON, UUID, enum, string, or numeric input. |
| `404` | Workplace, Character, Scene, Asset, document, version, or managed file not found. |
| `409` | `REVISION_CONFLICT` (with `current_revision`) or `DRAFT_PROTECTED` when AI regeneration would overwrite an author-edited identity draft. |
| `413` | Request body exceeds 4 MiB or an uploaded Asset exceeds `studio_asset_max_bytes`. |
| `422` | Invalid resource state, such as a parent or Asset link target from another Workplace. |
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

The React bundle in `studio-ui/` loads Workplaces, documents, Characters,
Scenes, and Assets from this API. Character Studio supports concept-first
creation, AI identity drafts with per-section review/regeneration, independent
identity saves, Outfit management, artwork Prompt review, single-image
generation, Avatar/Full Body/Outfit-reference approval and a Canon view.
Drafts are visually and structurally separate from Canon, and generated
artwork never changes identity by itself. Writing continues to autosave with
`expected_revision`, request inspiration, consume continuation SSE, and insert
accepted text only after the author approves it.

The Assets workspace provides grid and list views, image thumbnails, native
audio/video previews, document placeholders, upload state, type/tag filters,
metadata editing, and soft deletion. Asset detail shows every linked Character,
Scene, and Document. Characters and Scenes include a compact linked-assets
panel, while Writing exposes the same panel for the active Document. These
panels use the shared Asset-library picker and do not duplicate Character or
Scene data.

Each Scene has a prominent **Create Storyboard** / **Open Storyboard** action.
The Storyboard view shows large 16:9 shot cards, dramatic beat, action,
expression, performance, camera, visual description and image Prompt, Cast
selection, an explicit **Regenerate Storyboard** action with protected-content
confirmation, image generation and regeneration, and a return path to the
Scene. Generated images are loaded from the managed Asset file URL, so
refreshing the page or restarting the backend restores both the Storyboard and
its visuals. The Scene editor also exposes an approved-reference panel for
linked image Assets, and the Shot editor lets the author choose one Outfit per
Character. After generation, each Shot shows exactly which approved references
were selected and whether the adapter actually received image bytes; a
text-to-image-only engine displays that limitation instead of implying
image-to-image control.

## Tests

Run the persistence and HTTP integration suite with the fake engine:

```sh
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$PWD/lib:$PWD" guile test/studio/persistence.scm
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$PWD/lib:$PWD" guile test/studio/storyboard.scm
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$PWD/lib:$PWD" guile test/studio/character_studio.scm
GUILE_AUTO_COMPILE=0 GUILE_LOAD_PATH="$PWD/lib:$PWD" guile test/studio/visual_consistency.scm
./test/studio/run.sh
```

The runner creates temporary SQLite and Asset directories, starts and stops
Artanis twice, and checks document, Character, Scene, Cast, Storyboard,
generated-image Assets, Asset metadata, tags, managed file bytes, missing-file
errors, upload limits, temporary-file cleanup, strict AI storyboard schema
validation, author-edit/generated-image regeneration protection, explicit
acknowledgement, Character Studio drafts and locked-Canon handling, Outfit
default/reference transactions, fake image generation, Avatar approval, and
Full Body/Scene reference approval, bytevector reference tracing, approved-only
reference selection, and links across a restart. When Playwright is installed under `ui/node_modules`,
the same run also drives the bundled `/studio` page through concept-first
Character creation, draft approval, Outfit creation, fake artwork generation,
Avatar approval and a browser reload. It never enables SonicBoom or real GPU
image generation; the fake image adapter produces a real PNG without a GPU.
