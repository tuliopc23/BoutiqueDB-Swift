import urllib.request
import json

SPACE_ID = "aAzf3xNQu1mIpwQFEugD"
TOKEN = "gb_api_MQpMbzbUpF3pKKxaI5hLL9QkgvNZTHVpNS1NYBan"

def post_json(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

cr = post_json(f"https://api.gitbook.com/v1/spaces/{SPACE_ID}/change-requests", {"subject": "Test change 4"})
cr_id = cr["id"]

test_kinds = [
    {"kind": "add", "type": "page", "title": "Test Page"},
    {"kind": "add", "page": {"title": "Test Page"}},
    {"kind": "page-add", "title": "Test Page"},
    {"kind": "document-add", "title": "Test Page"},
    {"action": "add-page", "title": "Test Page"},
    {"mode": "add", "title": "Test Page"},
]

for change in test_kinds:
    try:
        res = post_json(f"https://api.gitbook.com/v1/spaces/{SPACE_ID}/change-requests/{cr_id}/content", {"changes": [change]})
        print("SUCCESS with format:", change)
        break
    except Exception as e:
        if hasattr(e, "read"):
            print(f"FAILED format {change}:", e.read().decode())
