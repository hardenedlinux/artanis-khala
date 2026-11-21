#!/usr/bin/env python3
"""Verify Studio data survives a backend restart."""

import json
import os
import urllib.request

port = os.environ["KHALA_STUDIO_TEST_PORT"]
state_path = os.environ["KHALA_STUDIO_STATE"]
with open(state_path, encoding="utf-8") as handle:
    expected = json.load(handle)

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
url = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['workplace_id']}/documents/{expected['document_id']}"
)
with opener.open(url, timeout=10) as response:
    payload = json.loads(response.read())["data"]

assert payload["revision"] == expected["revision"], payload
assert payload["content"] == expected["content"], payload
print("ok studio-data-survives-restart")

character_url = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['workplace_id']}/characters/{expected['character_id']}"
)
with opener.open(character_url, timeout=10) as response:
    character = json.loads(response.read())["data"]

assert character["name"] == "Mara Vale", character
assert character["literary_identity"]["fears"] == "Being lost at sea.", character
assert character["visual_identity"]["palette"].startswith("Sea blue"), character
print("ok studio-character-survives-restart")

scene_url = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['workplace_id']}/scenes/{expected['scene_id']}"
)
with opener.open(scene_url, timeout=10) as response:
    scene = json.loads(response.read())["data"]

assert scene["title"] == "The Drowned District", scene
assert scene["status"] == "ready", scene
assert scene["given_circumstances"]["place"] == "The northern harbor", scene
assert scene["dramatic_situation"]["turn"] == "The lamp is still warm.", scene
print("ok studio-scene-survives-restart")

cast_url = scene_url + "/cast"
with opener.open(cast_url, timeout=10) as response:
    cast = json.loads(response.read())["data"]

assert len(cast) == 1, cast
assert cast[0]["character_id"] == expected["character_id"], cast
assert cast[0]["objective"] == "Make Ilyan admit he lied.", cast
assert cast[0]["character_name"] == "Mara Vale", cast
print("ok studio-scene-cast-survives-restart")

with opener.open(scene_url + "/storyboard", timeout=10) as response:
    storyboard = json.loads(response.read())["data"]

assert len(storyboard["shots"]) == 4, storyboard
shot = next(
    item for item in storyboard["shots"] if item["id"] == expected["storyboard_shot_id"]
)
assert shot["status"] == "generated", shot
assert shot["asset_id"] == expected["storyboard_asset_id"], shot
assert shot["file_url"], shot
print("ok studio-storyboard-survives-restart")

with opener.open(
    "http://127.0.0.1:" + port + shot["file_url"], timeout=10
) as response:
    storyboard_image = response.read()

assert storyboard_image.startswith(b"\x89PNG\r\n\x1a\n"), storyboard_image[:16]
print("ok studio-storyboard-image-survives-restart")

asset_url = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['workplace_id']}/assets/{expected['asset_id']}"
)
with opener.open(asset_url, timeout=10) as response:
    asset = json.loads(response.read())["data"]

assert asset["name"] == "Mara portrait — canon", asset
assert asset["tags"] == ["canon", "portrait"], asset
assert asset["checksum"] == expected["asset_checksum"], asset
assert len(asset["links"]) == 3, asset
assert {link["resource_type"] for link in asset["links"]} == {
    "character", "scene", "document"
}, asset
print("ok studio-asset-survives-restart")

with opener.open("http://127.0.0.1:" + port + asset["file_url"], timeout=10) as response:
    file_bytes = response.read()
    content_type = response.headers.get("Content-Type", "")

assert content_type.startswith("image/png"), content_type
assert file_bytes.startswith(b"\x89PNG\r\n\x1a\n"), file_bytes[:16]
print("ok studio-asset-file-survives-restart")
