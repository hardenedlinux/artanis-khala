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
