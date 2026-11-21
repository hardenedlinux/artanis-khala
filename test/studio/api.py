#!/usr/bin/env python3
"""HTTP integration checks for the Khala Studio API.

Set KHALA_STUDIO_TEST_PORT to the test server port. The suite is run by
test/studio/run.sh, which starts Khala with the fake engine and a temporary
Studio database.
"""

import json
import os
import socket
import time
import urllib.error
import urllib.request
import uuid

PORT = os.environ.get("KHALA_STUDIO_TEST_PORT", "3188")
BASE = f"http://127.0.0.1:{PORT}"
STATE_PATH = os.environ.get("KHALA_STUDIO_STATE")
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(method, path, data=None):
    body = None if data is None else json.dumps(data).encode()
    headers = {"Content-Type": "application/json"} if body else {}
    req = urllib.request.Request(BASE + path, data=body, method=method, headers=headers)
    try:
        with OPENER.open(req, timeout=30) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, error.read(), dict(error.headers)


def json_request(method, path, data=None, expected=200):
    status, body, _ = request(method, path, data)
    assert status == expected, (method, path, status, body)
    return json.loads(body)["data"]


def check(name, condition):
    assert condition, name
    print(f"ok {name}")


capabilities = json_request("GET", "/studio/api/v1/capabilities")
check("capabilities", capabilities["api_version"] == 1 and capabilities["ai_available"])
check("fake-model", any(item["id"] == "fake" for item in capabilities["models"]))

status, page, _ = request("GET", "/studio")
check(
    "studio-shell",
    status == 200 and b"/studio/assets/studio-ui" in page,
)
for asset_path, content_type in (
    ("/studio/assets/studio-ui", "text/javascript"),
    ("/studio/assets/studio-ui-theme", "text/css"),
    ("/studio/assets/react", "text/javascript"),
    ("/studio/assets/react-dom", "text/javascript"),
):
    status, asset, headers = request("GET", asset_path)
    assert status == 200 and asset, (asset_path, status)
    assert headers.get("Content-Type", "").startswith(content_type), (
        asset_path,
        headers.get("Content-Type"),
    )
status, _, _ = request("GET", "/studio/assets/not-allowlisted")
check("studio-assets-allowlisted", status == 404)

workplace = json_request(
    "POST",
    "/studio/api/v1/workplaces",
    {"title": "API World", "description": "desc", "cover_color": "#713D3B"},
    201,
)
workplace_id = workplace["id"]
check("workplace-created", workplace["document_count"] == 0)
listed = json_request("GET", "/studio/api/v1/workplaces")
check("workplace-listed", any(item["id"] == workplace_id for item in listed))

updated_workplace = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}",
    {"description": "updated", "cover_asset_id": None},
)
check("workplace-updated", updated_workplace["description"] == "updated")

character = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/characters",
    {
        "name": "Mara Vale",
        "role": "Protagonist",
        "summary": "A cartographer returning to the coast.",
        "literary_identity": {
            "background": "Raised beside the northern harbor.",
            "personality": "Observant and guarded.",
            "goals": "Map the drowned district.",
        },
        "visual_identity": {
            "standard_appearance": "Tall, weathered blue coat.",
            "hair": "Dark, cut short.",
            "palette": "Sea blue, brass, wet stone.",
        },
        "vocal_identity": {
            "timbre": "Low and dry.",
            "pace": "Measured.",
        },
        "performance_identity": {
            "habits": "Taps the table twice before speaking.",
            "situations": "Goes quiet when challenged.",
        },
    },
    201,
)
character_id = character["id"]
check(
    "character-created",
    character["workplace_id"] == workplace_id
    and character["literary_identity"]["background"].startswith("Raised"),
)
characters = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/characters"
)
check("character-listed", any(item["id"] == character_id for item in characters))

updated_character = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{character_id}",
    {
        "role": "Point-of-view character",
        "literary_identity": {"fears": "Being lost at sea."},
    },
)
check(
    "character-identity-independent-update",
    updated_character["role"] == "Point-of-view character"
    and updated_character["literary_identity"]["fears"] == "Being lost at sea."
    and updated_character["literary_identity"]["background"].startswith("Raised")
    and updated_character["visual_identity"]["palette"].startswith("Sea blue")
    and updated_character["vocal_identity"]["timbre"] == "Low and dry."
    and updated_character["performance_identity"]["habits"].startswith("Taps"),
)
character_detail = json_request(
    "GET",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{character_id}",
)
check(
    "character-detail",
    character_detail["name"] == "Mara Vale"
    and character_detail["visual_identity"]["hair"] == "Dark, cut short.",
)

status, body, _ = request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{character_id}",
    {"visual_identity": {"unsupported_field": "value"}},
)
check(
    "character-identity-validated",
    status == 400 and json.loads(body)["error"]["code"] == "VALIDATION_ERROR",
)

other_workplace = json_request(
    "POST",
    "/studio/api/v1/workplaces",
    {"title": "Other World", "description": "", "cover_color": "#354B40"},
    201,
)
other_workplace_id = other_workplace["id"]
other_characters = json_request(
    "GET", f"/studio/api/v1/workplaces/{other_workplace_id}/characters"
)
check("character-workplace-isolated-list", other_characters == [])
for method, body in (("GET", None), ("PUT", {"summary": "wrong world"}), ("DELETE", None)):
    status, _, _ = request(
        method,
        f"/studio/api/v1/workplaces/{other_workplace_id}/characters/{character_id}",
        body,
    )
    assert status == 404, (method, status)
check("character-workplace-isolated-detail", True)

archived_character = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/characters",
    {"name": "Temporary Character"},
    201,
)
archived_character_id = archived_character["id"]
archived = json_request(
    "DELETE",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{archived_character_id}",
)
check("character-soft-deleted", bool(archived["archived_at"]))
characters_after_archive = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/characters"
)
check(
    "character-archive-hidden",
    all(item["id"] != archived_character_id for item in characters_after_archive),
)
status, _, _ = request(
    "GET",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{archived_character_id}",
)
check("archived-character-404", status == 404)

scene = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes",
    {
        "title": "The Drowned District",
        "summary": "A confrontation at the tide line.",
        "sort_order": 1,
        "status": "draft",
        "given_circumstances": {
            "time": "Before dawn",
            "place": "The northern harbor",
            "environment": "Fog and low tide",
            "background": "The district was abandoned ten years ago.",
            "prior_events": "Mara found the old survey map.",
        },
        "dramatic_situation": {
            "central_question": "Will Mara admit why she returned?",
            "primary_conflict": "Mara wants the truth; Ilyan wants her gone.",
            "turn": "Ilyan reveals the lighthouse was never abandoned.",
        },
        "dialogue": "MARA\nYou came back.",
        "direction": {
            "blocking": "Mara stays between Ilyan and the stairs.",
            "spatial": "A narrow pier above black water.",
            "performance_direction": "Speak quietly.",
            "camera": "Hold on the map in Mara's hand.",
        },
    },
    201,
)
scene_id = scene["id"]
check(
    "scene-created",
    scene["workplace_id"] == workplace_id
    and scene["given_circumstances"]["time"] == "Before dawn"
    and scene["direction"]["camera"].startswith("Hold"),
)
scenes = json_request("GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes")
check("scene-listed", any(item["id"] == scene_id for item in scenes))

updated_scene = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}",
    {
        "status": "ready",
        "dramatic_situation": {"turn": "The lamp is still warm."},
        "direction": {"spatial": "The tide has covered the lower stair."},
    },
)
check(
    "scene-updated-partially",
    updated_scene["status"] == "ready"
    and updated_scene["dramatic_situation"]["turn"] == "The lamp is still warm."
    and updated_scene["dramatic_situation"]["central_question"]
    == "Will Mara admit why she returned?"
    and updated_scene["direction"]["blocking"].startswith("Mara stays")
    and updated_scene["direction"]["spatial"].startswith("The tide"),
)

status, body, _ = request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}",
    {"given_circumstances": {"unsupported_field": "value"}},
)
check(
    "scene-nested-fields-validated",
    status == 400 and json.loads(body)["error"]["code"] == "VALIDATION_ERROR",
)
status, body, _ = request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}",
    {"status": "published"},
)
check(
    "scene-status-validated",
    status == 400 and json.loads(body)["error"]["code"] == "VALIDATION_ERROR",
)

cast = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/cast",
    {
        "cast": [
            {
                "character_id": character_id,
                "objective": "Make Ilyan admit he lied.",
                "action": "Ask a question he cannot answer.",
                "conflict": "Ilyan refuses to look at the map.",
                "emotional_state": "Controlled anger.",
                "performance_direction": "Do not raise her voice.",
                "subtext": "She already knows.",
                "sort_order": 0,
            }
        ]
    },
)
check(
    "scene-cast-created",
    len(cast) == 1
    and cast[0]["character_id"] == character_id
    and cast[0]["character_name"] == "Mara Vale"
    and cast[0]["objective"].startswith("Make Ilyan"),
)
cast_read = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/cast"
)
check("scene-cast-read", cast_read == cast)

second_scene = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes",
    {
        "title": "The Empty Lighthouse",
        "summary": "What remains after the argument.",
        "sort_order": 2,
    },
    201,
)
second_scene_id = second_scene["id"]
json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/cast",
    {
        "cast": [
            {
                "character_id": character_id,
                "objective": "Protect the evidence.",
                "action": "Block the stair.",
                "conflict": "She cannot guard it forever.",
                "emotional_state": "Exhausted resolve.",
            }
        ]
    },
)
check(
    "same-character-multiple-scenes",
    len(json_request(
        "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/cast"
    )) == 1
    and len(json_request(
        "GET",
        f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/cast",
    )) == 1,
)

other_character = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{other_workplace_id}/characters",
    {"name": "Ilyan Ro", "role": "Antagonist"},
    201,
)
status, body, _ = request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/cast",
    {
        "cast": [
            {"character_id": character_id, "objective": "Valid replacement."},
            {
                "character_id": other_character["id"],
                "objective": "Cross-workplace reference.",
            },
        ]
    },
)
error = json.loads(body)["error"]
check(
    "scene-cast-rejects-other-workplace",
    status == 422 and error["code"] == "INVALID_CAST_CHARACTER",
)
cast_after_rejection = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/cast"
)
check(
    "scene-cast-transaction-preserved",
    len(cast_after_rejection) == 1
    and cast_after_rejection[0]["objective"] == "Protect the evidence.",
)
status, body, _ = request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/cast",
    {
        "cast": [
            {"character_id": character_id, "objective": "First entry."},
            {"character_id": character_id, "objective": "Duplicate entry."},
        ]
    },
)
check(
    "scene-cast-rejects-duplicates",
    status == 400 and json.loads(body)["error"]["code"] == "VALIDATION_ERROR",
)

for method, body in (("GET", None), ("PUT", {"summary": "wrong world"}), ("DELETE", None)):
    status, _, _ = request(
        method,
        f"/studio/api/v1/workplaces/{other_workplace_id}/scenes/{scene_id}",
        body,
    )
    assert status == 404, (method, status)
check("scene-workplace-isolated", True)

deleted_scene = json_request(
    "DELETE",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}",
)
check("scene-soft-deleted", bool(deleted_scene["deleted_at"]))
status, _, _ = request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}"
)
check("deleted-scene-404", status == 404)
json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/characters/{character_id}"
)
check("scene-delete-keeps-character", True)

manuscript = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/documents",
    {
        "parent_id": None,
        "kind": "manuscript",
        "title": "Book",
        "content_format": "markdown",
        "content": "hello world",
        "sort_order": 0,
    },
    201,
)
document_id = manuscript["id"]
chapter = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/documents",
    {
        "parent_id": document_id,
        "kind": "chapter",
        "title": "Chapter One",
        "content_format": "markdown",
        "content": "",
        "sort_order": 1,
    },
    201,
)
check("nested-document", chapter["parent_id"] == document_id)

documents = json_request("GET", f"/studio/api/v1/workplaces/{workplace_id}/documents")
check("document-list-has-no-content", all("content" not in item for item in documents))
check("document-list-has-word-count", documents[0]["word_count"] == 2)

full = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}"
)
check("document-content", full["content"] == "hello world")

same = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}",
    {
        "title": "Book",
        "content": "hello world",
        "content_format": "markdown",
        "expected_revision": full["revision"],
    },
)
check("no-op-revision", same["revision"] == full["revision"])

changed = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}",
    {
        "title": "Book",
        "content": "hello brave world",
        "content_format": "markdown",
        "expected_revision": same["revision"],
    },
)
check("save-increments-revision", changed["revision"] == full["revision"] + 1)

status, body, _ = request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}",
    {
        "title": "Book",
        "content": "stale overwrite",
        "content_format": "markdown",
        "expected_revision": full["revision"],
    },
)
conflict = json.loads(body)
check(
    "stale-revision-conflicts",
    status == 409
    and conflict["error"]["code"] == "REVISION_CONFLICT"
    and conflict["error"]["current_revision"] == changed["revision"],
)
current = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}"
)
check("stale-write-does-not-overwrite", current["content"] == "hello brave world")

version = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/versions",
    {"label": "Checkpoint", "source": "checkpoint"},
    201,
)
version_id = version["id"]
versions = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/versions"
)
check("version-list-has-no-content", all("content" not in item for item in versions))

later = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}",
    {
        "title": "Book",
        "content": "later content",
        "content_format": "markdown",
        "expected_revision": changed["revision"],
    },
)
historical = json_request(
    "GET",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/versions/{version_id}",
)
check("version-immutable", historical["content"] == "hello brave world")

restored = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/versions/{version_id}/restore",
    {},
)
check(
    "restore-new-revision",
    restored["revision"] == later["revision"] + 1
    and restored["content"] == "hello brave world",
)
historical_after = json_request(
    "GET",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/versions/{version_id}",
)
check("restore-preserves-history", historical_after["content"] == "hello brave world")

inspiration = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/ai/inspire",
    {
        "model": "fake",
        "selected_text": "hello",
        "context_before": "hello brave world",
        "instruction": "Give several directions.",
    },
)
check("inspire-content", bool(inspiration["content"]))
unchanged = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}"
)
check("inspire-does-not-write", unchanged["content"] == "hello brave world")

body = json.dumps(
    {
        "model": "fake",
        "context_before": "hello brave world",
        "instruction": "Continue.",
        "max_tokens": 64,
    }
).encode()
stream_request = urllib.request.Request(
    BASE
    + f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/ai/continue",
    data=body,
    method="POST",
    headers={"Content-Type": "application/json"},
)
with OPENER.open(stream_request, timeout=30) as response:
    assert response.headers.get("Content-Type", "").startswith("text/event-stream")
    events = response.read().decode()
check("continue-meta", "event: meta" in events)
check("continue-tokens", "event: token" in events)
check("continue-done", "event: done" in events)
unchanged = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}"
)
check("continue-does-not-write", unchanged["content"] == "hello brave world")

# Closing a stream must not leave the document changed. The server-side
# cancellation callback is exercised by closing the socket early.
disconnect_request = urllib.request.Request(
    BASE
    + f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/ai/continue",
    data=json.dumps(
        {
            "context_before": " ".join(["word"] * 1200),
            "instruction": "Continue.",
            "max_tokens": 256,
        }
    ).encode(),
    method="POST",
    headers={"Content-Type": "application/json"},
)
try:
    response = OPENER.open(disconnect_request, timeout=5)
    response.read(64)
    response.close()
except Exception:
    pass
time.sleep(0.2)
unchanged = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}"
)
check("disconnect-does-not-write", unchanged["content"] == "hello brave world")

for path in (
    f"/studio/api/v1/workplaces/{uuid.uuid4()}",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{uuid.uuid4()}",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{uuid.uuid4()}",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/cast/{uuid.uuid4()}",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{uuid.uuid4()}",
    f"/studio/api/v1/workplaces/{workplace_id}/documents/{document_id}/versions/{uuid.uuid4()}",
):
    status, _, _ = request("GET", path)
    assert status == 404, (path, status)
check("unknown-resources-404", True)

for path in ("/", "/khala", "/khala/api/system", "/api/version", "/v1/models", "/object_info", "/studio"):
    status, _, _ = request("GET", path)
    assert status == 200, (path, status)
check("existing-routes-preserved", True)

if STATE_PATH:
    with open(STATE_PATH, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "workplace_id": workplace_id,
                "character_id": character_id,
                "scene_id": scene_id,
                "document_id": document_id,
                "revision": unchanged["revision"],
                "content": unchanged["content"],
            },
            handle,
        )

print("Khala Studio HTTP integration tests passed")
