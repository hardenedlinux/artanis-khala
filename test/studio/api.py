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
                "document_id": document_id,
                "revision": unchanged["revision"],
                "content": unchanged["content"],
            },
            handle,
        )

print("Khala Studio HTTP integration tests passed")
