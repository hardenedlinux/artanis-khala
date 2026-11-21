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
import base64
import urllib.error
import urllib.request
import uuid

PORT = os.environ.get("KHALA_STUDIO_TEST_PORT", "3188")
BASE = f"http://127.0.0.1:{PORT}"
STATE_PATH = os.environ.get("KHALA_STUDIO_STATE")
ASSETS_DIR = os.environ["KHALA_STUDIO_TEST_ASSETS_DIR"]
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request_raw(method, path, body=None, headers=None):
    req = urllib.request.Request(BASE + path, data=body, method=method, headers=headers or {})
    try:
        with OPENER.open(req, timeout=30) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, error.read(), dict(error.headers)


def request(method, path, data=None):
    body = None if data is None else json.dumps(data).encode()
    headers = {"Content-Type": "application/json"} if body else {}
    return request_raw(method, path, body, headers)


def multipart_upload(path, fields, filename, content, mime="image/png"):
    boundary = f"----khala{uuid.uuid4().hex}"
    chunks = []
    for name, value in fields.items():
        chunks.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            str(value).encode(),
            b"\r\n",
        ])
    chunks.extend([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode(),
        f"Content-Type: {mime}\r\n\r\n".encode(),
        content,
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    body = b"".join(chunks)
    return request_raw(
        "POST", path, body,
        {"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )


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

storyboard = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard",
    {},
)
shots = storyboard["shots"]
check("storyboard-created", len(shots) == 4 and storyboard["generation_available"])
check(
    "storyboard-has-dramatic-shot-fields",
    all(
        shot["dramatic_beat"]
        and shot["action"]
        and shot["expression"]
        and shot["performance"]
        and shot["source"] == "deterministic"
        and shot["author_edited"] is False
        for shot in shots
    ),
)
check(
    "storyboard-uses-existing-context",
    "Tall, weathered blue coat." in shots[0]["image_prompt"]
    and "Make Ilyan admit he lied." in shots[0]["image_prompt"]
    and "The northern harbor" in shots[0]["image_prompt"]
    and "Raised beside the northern harbor." in shots[0]["image_prompt"]
    and "Taps the table twice before speaking." in shots[0]["image_prompt"],
)
scene_with_board = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}"
)
check("storyboard-count-on-scene", scene_with_board["storyboard_count"] == 4)

edited_shots = json.loads(json.dumps(shots))
edited_shots[0]["content"] = "Mara steps off the gangway into the drowned district."
edited_shots[0]["image_prompt"] += "\nAUTHOR EDIT: hold on the wet map in her hand."
edited_board = json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard",
    {"shots": edited_shots},
)
check(
    "storyboard-edited-and-saved",
    edited_board["shots"][0]["content"].startswith("Mara steps")
    and "AUTHOR EDIT" in edited_board["shots"][0]["image_prompt"]
    and edited_board["shots"][0]["author_edited"] is True,
)
status, body, _ = request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard",
    {"force": True},
)
check(
    "storyboard-regeneration-protects-author-edits",
    status == 422
    and json.loads(body)["error"]["code"] == "STORYBOARD_PROTECTED",
)
protected_board = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard"
)
check(
    "storyboard-protected-content-not-overwritten",
    protected_board["shots"][0]["content"].startswith("Mara steps")
    and "AUTHOR EDIT" in protected_board["shots"][0]["image_prompt"],
)
shot_id = edited_board["shots"][0]["id"]
generated = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard/shots/{shot_id}/image",
)
check(
    "storyboard-image-generated",
    generated["shot"]["status"] == "generated"
    and generated["asset"]["source"] == "generated"
    and generated["asset"]["asset_type"] == "image"
    and generated["shot"]["asset_id"] == generated["asset"]["id"],
)
status, image_bytes, image_headers = request("GET", generated["asset"]["file_url"])
check(
    "storyboard-image-served",
    status == 200
    and image_bytes.startswith(b"\x89PNG\r\n\x1a\n")
    and image_headers.get("Content-Type", "").startswith("image/png"),
)
scene_after_generation = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}"
)
check(
    "storyboard-generation-preserves-scene",
    scene_after_generation["dramatic_situation"]["turn"] == "The lamp is still warm."
    and scene_after_generation["dialogue"] == "MARA\nYou came back.",
)
linked_assets = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/assets"
)
check(
    "storyboard-image-linked-to-scene",
    any(asset["id"] == generated["asset"]["id"] for asset in linked_assets),
)
regenerated = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard/shots/{shot_id}/image",
)
check(
    "storyboard-image-regenerated",
    regenerated["shot"]["asset_id"] != generated["shot"]["asset_id"],
)
old_asset = json_request(
    "GET", f"/studio/api/v1/workplaces/{workplace_id}/assets/{generated['asset']['id']}"
)
check("storyboard-regeneration-keeps-old-asset", old_asset["id"] == generated["asset"]["id"])
status, body, _ = request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard",
    {"force": True},
)
check(
    "storyboard-regeneration-protects-generated-shot",
    status == 422
    and json.loads(body)["error"]["code"] == "STORYBOARD_PROTECTED",
)
status, body, _ = request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{scene_id}/storyboard/shots/{uuid.uuid4()}/image",
)
check("storyboard-unknown-shot-404", status == 404)

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

second_board = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/storyboard",
    {},
)
second_edited = json.loads(json.dumps(second_board))
second_edited["shots"][0]["dramatic_beat"] = "Author-shaped beat."
json_request(
    "PUT",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/storyboard",
    {"shots": second_edited["shots"]},
)
status, body, _ = request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/storyboard",
    {"force": True},
)
check(
    "storyboard-protected-requires-acknowledgement",
    status == 422
    and json.loads(body)["error"]["code"] == "STORYBOARD_PROTECTED",
)
acknowledged = json_request(
    "POST",
    f"/studio/api/v1/workplaces/{workplace_id}/scenes/{second_scene_id}/storyboard",
    {"force": True, "acknowledge_protected": True},
)
check(
    "storyboard-regenerates-after-explicit-acknowledgement",
    len(acknowledged["shots"]) == 4
    and acknowledged["shots"][0]["id"] != second_board["shots"][0]["id"],
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

PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)
assets_path = f"/studio/api/v1/workplaces/{workplace_id}/assets"
status, body, _ = multipart_upload(
    f"{assets_path}/upload",
    {
        "name": "Mara portrait",
        "description": "Approved visual reference for the coast sequence.",
        "asset_type": "image",
        "width": "1",
        "height": "1",
        "author": "Studio author",
        "notes": "Keep the coat silhouette consistent.",
        "tags": '["portrait", "mara"]',
        "generation_metadata": '{"workflow":"manual-reference"}',
    },
    "mara-portrait.png",
    PNG_BYTES,
)
assert status == 201, (status, body)
asset = json.loads(body)["data"]
asset_id = asset["id"]
check(
    "asset-uploaded",
    asset["asset_type"] == "image"
    and asset["source"] == "upload"
    and asset["mime_type"] == "image/png"
    and asset["file_size"] == len(PNG_BYTES)
    and len(asset["checksum"]) == 64
    and asset["tags"] == ["mara", "portrait"]
    and asset["generation_metadata"]["workflow"] == "manual-reference",
)
check(
    "asset-file-url-managed",
    asset["file_url"].startswith(f"/studio/api/v1/workplaces/{workplace_id}/assets/")
    and asset["storage_key"].endswith(".png")
    and "/" not in asset["storage_key"],
)
asset_file_path = asset["file_url"]
status, file_body, file_headers = request_raw("GET", asset_file_path)
check(
    "asset-file-served",
    status == 200
    and file_body == PNG_BYTES
    and file_headers.get("Content-Type", "").startswith("image/png")
    and file_headers.get("X-Content-Type-Options") == "nosniff"
    and "inline" in file_headers.get("Content-Disposition", ""),
)
asset_list = json_request("GET", assets_path)
check("asset-listed", any(item["id"] == asset_id for item in asset_list))
asset_detail = json_request("GET", f"{assets_path}/{asset_id}")
check("asset-detail", asset_detail["name"] == "Mara portrait")

updated_asset = json_request(
    "PUT",
    f"{assets_path}/{asset_id}",
    {
        "name": "Mara portrait — canon",
        "description": "Approved visual canon.",
        "author": "Mara's author",
        "notes": "Use for scenes in the northern harbor.",
        "tags": ["canon", "portrait"],
        "width": 1,
        "height": 1,
    },
)
check(
    "asset-updated",
    updated_asset["name"] == "Mara portrait — canon"
    and updated_asset["author"] == "Mara's author"
    and updated_asset["tags"] == ["canon", "portrait"],
)

for resource_type, resource_id in (
    ("character", character_id),
    ("scene", scene_id),
    ("document", document_id),
):
    link = json_request(
        "POST",
        f"{assets_path}/{asset_id}/links",
        {"resource_type": resource_type, "resource_id": resource_id},
        201,
    )
    check(f"asset-linked-{resource_type}", link["resource_id"] == resource_id)
linked_detail = json_request("GET", f"{assets_path}/{asset_id}")
check("asset-has-multiple-links", len(linked_detail["links"]) == 3)
for resource_type, resource_path, resource_id in (
    ("character", "characters", character_id),
    ("scene", "scenes", scene_id),
    ("document", "documents", document_id),
):
    linked_assets = json_request(
        "GET",
        f"/studio/api/v1/workplaces/{workplace_id}/{resource_path}/{resource_id}/assets",
    )
    check(
        f"asset-visible-from-{resource_type}",
        any(item["id"] == asset_id for item in linked_assets),
    )

status, body, _ = request(
    "POST",
    f"{assets_path}/{asset_id}/links",
    {"resource_type": "character", "resource_id": other_character["id"]},
)
check(
    "asset-link-rejects-other-workplace",
    status == 422 and json.loads(body)["error"]["code"] == "INVALID_RESOURCE",
)
check(
    "asset-workplace-isolated-list",
    json_request("GET", f"/studio/api/v1/workplaces/{other_workplace_id}/assets") == [],
)
for method in ("GET", "DELETE"):
    status, _, _ = request(
        method,
        f"/studio/api/v1/workplaces/{other_workplace_id}/assets/{asset_id}",
    )
    assert status == 404, (method, status)
status, _, _ = request(
    "GET",
    f"/studio/api/v1/workplaces/{other_workplace_id}/assets/{asset_id}/file",
)
check("asset-workplace-isolated-detail", status == 404)

removed_link = json_request(
    "DELETE",
    f"{assets_path}/{asset_id}/links/scene/{scene_id}",
)
check("asset-link-removed", removed_link["removed"])
json_request(
    "POST",
    f"{assets_path}/{asset_id}/links",
    {"resource_type": "scene", "resource_id": scene_id},
    201,
)

status, body, _ = multipart_upload(
    f"{assets_path}/upload",
    {"name": "Temporary reference", "tags": "temporary"},
    "temporary.png",
    PNG_BYTES,
)
assert status == 201, (status, body)
temporary_asset = json.loads(body)["data"]
temporary_asset_id = temporary_asset["id"]
json_request(
    "POST",
    f"{assets_path}/{temporary_asset_id}/links",
    {"resource_type": "character", "resource_id": character_id},
    201,
)
deleted_asset = json_request("DELETE", f"{assets_path}/{temporary_asset_id}")
check("asset-soft-deleted", bool(deleted_asset["archived_at"]))
status, _, _ = request_raw("GET", temporary_asset["file_url"])
check("asset-file-removed-on-delete", status == 404)
character_assets_after_delete = json_request(
    "GET",
    f"/studio/api/v1/workplaces/{workplace_id}/characters/{character_id}/assets",
)
check(
    "asset-delete-clears-links",
    all(item["id"] != temporary_asset_id for item in character_assets_after_delete),
)
status, _, _ = request("GET", f"{assets_path}/{temporary_asset_id}")
check("deleted-asset-404", status == 404)

metadata_asset = json_request(
    "POST",
    assets_path,
    {
        "name": "Research notes index",
        "description": "A metadata-only reference entry.",
        "asset_type": "document",
        "source": "imported",
        "tags": ["research"],
    },
    201,
)
check(
    "asset-metadata-only",
    metadata_asset["has_file"] is False and metadata_asset["file_url"] is None,
)
status, body, _ = request(
    "POST",
    assets_path,
    {"name": "Forbidden fields", "storage_key": "../../etc/passwd"},
)
check(
    "asset-rejects-client-paths",
    status == 400 and json.loads(body)["error"]["code"] == "VALIDATION_ERROR",
)

for filename, content, mime, expected_code in (
    ("empty.png", b"", "image/png", "INVALID_UPLOAD"),
    ("wrong.txt", b"plain text", "image/png", "MIME_MISMATCH"),
    ("fake.png", b"not actually a png", "image/png", "INVALID_CONTENT"),
    ("unsafe.html", b"<script>alert(1)</script>", "text/html", "UNSUPPORTED_MEDIA_TYPE"),
):
    status, body, _ = multipart_upload(
        f"{assets_path}/upload", {"name": "Rejected upload"}, filename, content, mime
    )
    check(
        f"upload-rejects-{filename}",
        status == 400 and json.loads(body)["error"]["code"] == expected_code,
    )
status, body, _ = multipart_upload(
    f"{assets_path}/upload",
    {"name": "Wrong declared type"},
    "typing.png",
    PNG_BYTES,
    "image/png",
)
assert status == 201, (status, body)
extra_asset = json.loads(body)["data"]
wrong_type_status, wrong_type_body, _ = multipart_upload(
    f"{assets_path}/upload",
    {"name": "Wrong type", "asset_type": "document"},
    "wrong-type.png",
    PNG_BYTES,
    "image/png",
)
check(
    "upload-rejects-type-mismatch",
    wrong_type_status == 400
    and json.loads(wrong_type_body)["error"]["code"] == "TYPE_MISMATCH",
)
json_request("DELETE", f"{assets_path}/{extra_asset['id']}")

status, body, _ = multipart_upload(
    f"{assets_path}/upload",
    {"name": "Oversized image"},
    "oversized.png",
    PNG_BYTES + (b"\0" * (4 * 1024 * 1024 + 1)),
    "image/png",
)
check(
    "upload-rejects-oversize",
    status == 413 and json.loads(body)["error"]["code"] == "FILE_TOO_LARGE",
)

status, body, _ = multipart_upload(
    f"{assets_path}/upload",
    {"name": "Missing managed file"},
    "missing-file.png",
    PNG_BYTES,
    "image/png",
)
assert status == 201, (status, body)
missing_file_asset = json.loads(body)["data"]
missing_file_path = os.path.join(ASSETS_DIR, missing_file_asset["storage_key"])
assert os.path.isfile(missing_file_path), missing_file_path
os.unlink(missing_file_path)
status, body, _ = request("GET", missing_file_asset["file_url"])
check(
    "asset-missing-file-404",
    status == 404 and json.loads(body)["error"]["code"] == "ASSET_FILE_MISSING",
)
json_request("DELETE", f"{assets_path}/{missing_file_asset['id']}")
check(
    "asset-upload-temporary-clean",
    not [name for name in os.listdir(ASSETS_DIR) if name.startswith(".upload-")],
)

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
    f"/studio/api/v1/workplaces/{workplace_id}/assets/{uuid.uuid4()}",
    f"/studio/api/v1/workplaces/{workplace_id}/assets/{uuid.uuid4()}/file",
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
                "asset_id": asset_id,
                "storyboard_asset_id": regenerated["shot"]["asset_id"],
                "storyboard_shot_id": shot_id,
                "asset_checksum": asset["checksum"],
                "revision": unchanged["revision"],
                "content": unchanged["content"],
            },
            handle,
        )

print("Khala Studio HTTP integration tests passed")
