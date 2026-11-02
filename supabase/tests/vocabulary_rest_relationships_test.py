"""Check the real clients' embedding queries against the deployed Supabase schema.

Uses the app's publishable key. Optional SUPABASE_TEST_ACCESS_TOKEN allows a
signed-in read; without it, permission-denied on the private membership tables is
expected *after* PostgREST has successfully resolved the relationships.
No data is written and response contents / credentials are never printed.
"""

import json
import os
import re
import ssl
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
client = (ROOT / "Omninary/SupabaseManager.swift").read_text()
base_url = re.search(r'supabaseURL: URL\(string: "([^"]+)"', client).group(1)
publishable_key = re.search(r'supabaseKey: "([^"]+)"', client).group(1)
access_token = os.environ.get("SUPABASE_TEST_ACCESS_TOKEN")
hint = "topics!vocab_catalog_topic_id_fkey("
ssl_context = ssl.create_default_context()
# Python.org installations on macOS may not have imported the system CA bundle.
# Supplement trusted roots while keeping certificate verification enabled.
if sys.platform == "darwin" and Path("/etc/ssl/cert.pem").is_file():
    ssl_context.load_verify_locations("/etc/ssl/cert.pem")


def request(table, selection):
    headers = {"apikey": publishable_key}
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    url = f"{base_url}/rest/v1/{table}?{urlencode({'select': selection, 'limit': 1})}"
    try:
        with urlopen(Request(url, headers=headers), timeout=20, context=ssl_context) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        return error.code, json.load(error)


swift = (ROOT / "Omninary/Repositories.swift").read_text()
swift_user = re.search(r'let selectColumns = """(.*?)"""', swift, re.S).group(1)
swift_catalog = re.search(r'\.select\("(id,created_at,topic_id,[^"]+)"\)', swift).group(1)
web_user_source = (ROOT / "admin-web/src/lib/userApi.ts").read_text()
web_catalog = re.search(r"const catalogSelect = `(.*?)`;", web_user_source, re.S).group(1)
web_user = re.search(r"const userVocabularySelect = `(.*?)`;", web_user_source, re.S).group(1)
web_user = web_user.replace("${catalogSelect}", web_catalog)
web_admin = re.search(
    r"const catalogSelect = `(.*?)`;",
    (ROOT / "admin-web/src/lib/adminApi.ts").read_text(), re.S,
).group(1)

cases = [
    ("iOS saved meanings", "user_vocabulary", swift_user),
    ("iOS system catalog", "vocab_catalog", swift_catalog),
    ("web saved meanings", "user_vocabulary", web_user),
    ("web admin catalog", "vocab_catalog", web_admin),
]

for label, table, selection in cases:
    selection = re.sub(r"\s+", "", selection)
    assert hint in selection, f"{label}: direct legacy topic relationship must be explicit"
    old_status, old_payload = request(table, selection.replace(hint, "topics("))
    assert old_payload.get("code") == "PGRST201", f"{label}: ambiguity control did not reproduce"
    status, payload = request(table, selection)
    if status == 200:
        assert isinstance(payload, list), f"{label}: unexpected response shape"
        print(f"PASS: {label}: query resolved and returned an array")
    else:
        assert not access_token, f"{label}: signed-in query failed ({status})"
        assert isinstance(payload, dict) and payload.get("code") == "42501", f"{label}: query failed ({status})"
        assert "permission denied for table" in payload.get("message", ""), f"{label}: unexpected permission failure"
        print(f"PASS: {label}: query resolved; anonymous membership read correctly denied")

# This direct embedding needs no membership-table access. The explicit selector
# must also preserve the JSON key expected by the existing client decoders.
status, payload = request("vocab_catalog", "id,topics!vocab_catalog_topic_id_fkey(id,name)")
assert status == 200 and isinstance(payload, list), "Direct topic query did not succeed"
assert all("topics" in row for row in payload), "The response key changed"
print("PASS: explicit direct-topic query returned HTTP 200")
print("PASS: 5 live relationship checks; old queries reproduced PGRST201; no writes")
