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
assert studio_character["full_body_asset_id"] == (
    expected["studio_full_body_asset_id"]
), studio_character
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
    expected["studio_avatar_asset_id"],
    expected["studio_outfit_asset_id"],
    expected["studio_full_body_asset_id"],
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
assert character_canon["full_body"]["id"] == (
    expected["studio_full_body_asset_id"]
), character_canon
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
assert scene["reference_asset_ids"] == [expected["scene_reference_asset_id"]], scene
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
assert shot["reference_usage"]["applied"] is True, shot
assert [
    entry["asset_id"] for entry in shot["reference_usage"]["references"]
] == [expected["scene_reference_asset_id"]], shot
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

settings_url = "http://127.0.0.1:" + port + "/studio/api/v1/settings"
with opener.open(settings_url, timeout=10) as response:
    settings = json.loads(response.read())["data"]

profile = next(
    item for item in settings["llm_profiles"]
    if item["id"] == expected["model_profile_id"]
)
assert profile["name"] == "DeepSeek Author Rewrite", profile
assert profile["model_id"] == "deepseek-chat", profile
assert profile["api_key_configured"] is True, profile
assert profile["api_key_masked"], profile
assert "api_key" not in profile, profile
embedding_profile = next(
    item for item in settings["embedding_profiles"]
    if item["id"] == expected["embedding_profile_id"]
)
assert embedding_profile["dimensions"] == 1536, embedding_profile
assert embedding_profile["api_key_configured"] is True, embedding_profile
assert settings["default_embedding_profile_id"] == embedding_profile["id"], settings
print("ok studio-model-settings-survive-restart")

extracted_scene_url = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['workplace_id']}/scenes/{expected['extraction_scene_id']}"
)
with opener.open(extracted_scene_url, timeout=10) as response:
    extracted_scene = json.loads(response.read())["data"]

assert extracted_scene["source_document_id"] == expected["document_id"], extracted_scene
assert (
    extracted_scene["source_document_revision"] == expected["extraction_revision"]
), extracted_scene
assert extracted_scene["source_text_snapshot"] == "hello brave", extracted_scene
assert extracted_scene["given_circumstances"]["place"].startswith(
    "A narrow repair workshop"
), extracted_scene
print("ok studio-scene-extraction-source-survives-restart")

demo_base = (
    f"http://127.0.0.1:{port}/studio/api/v1/workplaces/"
    f"{expected['demo_workplace_id']}"
)
with opener.open(
    demo_base + "/documents/" + expected["demo_document_id"], timeout=10
) as response:
    demo_document = json.loads(response.read())["data"]
assert demo_document["content"] == expected["demo_content"], demo_document
assert demo_document["revision"] == expected["demo_revision"], demo_document

with opener.open(demo_base + "/characters", timeout=10) as response:
    demo_characters = json.loads(response.read())["data"]
assert {character["id"] for character in demo_characters} == set(
    expected["demo_character_ids"]
), demo_characters

with opener.open(
    demo_base + "/scenes/" + expected["demo_scene_id"], timeout=10
) as response:
    demo_scene = json.loads(response.read())["data"]
assert demo_scene["source_document_id"] == expected["demo_document_id"], demo_scene

with opener.open(
    demo_base + "/scenes/" + expected["demo_scene_id"] + "/cast", timeout=10
) as response:
    demo_cast = json.loads(response.read())["data"]
assert len(demo_cast) == 3, demo_cast

with opener.open(
    demo_base + "/scenes/" + expected["demo_scene_id"] + "/storyboard", timeout=10
) as response:
    demo_storyboard = json.loads(response.read())["data"]
assert len(demo_storyboard["shots"]) == expected["demo_storyboard_count"], demo_storyboard
assert all(shot["source"] == "sample" for shot in demo_storyboard["shots"]), demo_storyboard

with opener.open(
    demo_base + "/assets/" + expected["demo_asset_id"], timeout=10
) as response:
    demo_asset = json.loads(response.read())["data"]
assert demo_asset["checksum"] == expected["demo_asset_checksum"], demo_asset
assert demo_asset["generation_metadata"]["generated_by_model"] is False, demo_asset
assert any(
    link["resource_type"] == "scene"
    and link["resource_id"] == expected["demo_scene_id"]
    for link in demo_asset["links"]
), demo_asset

with opener.open(
    "http://127.0.0.1:" + port + demo_asset["file_url"], timeout=10
) as response:
    demo_image = response.read()
assert demo_image.startswith(b"\x89PNG\r\n\x1a\n"), demo_image[:16]
print("ok studio-sample-story-survives-restart")
