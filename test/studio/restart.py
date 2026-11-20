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
