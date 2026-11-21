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

studio_character_url = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['workplace_id']}/characters/{expected['studio_character_id']}"
)
with opener.open(studio_character_url, timeout=10) as response:
    studio_character = json.loads(response.read())["data"]

assert studio_character["name"] == "Sera Voss", studio_character
assert studio_character["visual_identity"]["face"] == (
    "A locked angular face with a burn scar."
), studio_character
assert studio_character["visual_identity"]["standard_appearance"], studio_character
assert studio_character["avatar_asset_id"] == expected["studio_avatar_asset_id"], studio_character
print("ok studio-character-studio-survives-restart")

with opener.open(studio_character_url + "/outfits", timeout=10) as response:
    outfits = json.loads(response.read())["data"]

assert len(outfits) == 2, outfits
outfit = next(item for item in outfits if item["id"] == expected["studio_outfit_id"])
assert outfit["is_default"] is True, outfit
assert outfit["colors"] == ["charcoal", "brass"], outfit
assert outfit["components"] == ["long coat", "work trousers"], outfit
assert outfit["reference_asset_id"] == expected["studio_outfit_asset_id"], outfit
print("ok studio-outfits-survive-restart")

with opener.open(studio_character_url + "/artworks", timeout=10) as response:
    character_artworks = json.loads(response.read())["data"]

assert {
    asset["id"] for asset in character_artworks
} == {
    expected["studio_avatar_asset_id"], expected["studio_outfit_asset_id"]
}, character_artworks
print("ok studio-character-artworks-survive-restart")

with opener.open(studio_character_url + "/ai/drafts", timeout=10) as response:
    character_drafts = json.loads(response.read())["data"]

assert {draft["section"] for draft in character_drafts} == {
    "literary_identity", "vocal_identity", "performance_identity"
}, character_drafts
print("ok studio-character-drafts-survive-restart")

with opener.open(studio_character_url + "/canon", timeout=10) as response:
    character_canon = json.loads(response.read())["data"]

assert character_canon["avatar"]["id"] == expected["studio_avatar_asset_id"], character_canon
print("ok studio-character-canon-survives-restart")

with opener.open(
    "http://127.0.0.1:" + port + character_canon["avatar"]["file_url"], timeout=10
) as response:
    character_artwork = response.read()

assert character_artwork.startswith(b"\x89PNG\r\n\x1a\n"), character_artwork[:16]
print("ok studio-character-artwork-file-survives-restart")

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
