import os
import json
import urllib.request

SPACE_ID = "aAzf3xNQu1mIpwQFEugD"
TOKEN = "gb_api_MQpMbzbUpF3pKKxaI5hLL9QkgvNZTHVpNS1NYBan"
DOCS_DIR = "/Users/tuliopinheirocunha/Developer/BoutiqueDB-Swift/docs"

def post_json(url, data, method="POST"):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        if hasattr(e, "read"):
            print("Error body:", e.read().decode())
        raise e

def markdown_to_gitbook_document(text):
    nodes = []
    lines = text.split("\n")
    for line in lines:
        if line.startswith("# "):
            nodes.append({
                "object": "block",
                "type": "heading-1",
                "data": {},
                "nodes": [{"object": "text", "leaves": [{"object": "leaf", "text": line[2:], "marks": []}]}]
            })
        elif line.startswith("## "):
            nodes.append({
                "object": "block",
                "type": "heading-2",
                "data": {},
                "nodes": [{"object": "text", "leaves": [{"object": "leaf", "text": line[3:], "marks": []}]}]
            })
        elif line.startswith("### "):
            nodes.append({
                "object": "block",
                "type": "heading-3",
                "data": {},
                "nodes": [{"object": "text", "leaves": [{"object": "leaf", "text": line[4:], "marks": []}]}]
            })
        elif line.strip():
            nodes.append({
                "object": "block",
                "type": "paragraph",
                "data": {},
                "nodes": [{"object": "text", "leaves": [{"object": "leaf", "text": line, "marks": []}]}]
            })
    return {"object": "document", "data": {"schemaVersion": 9}, "nodes": nodes}

print("Creating change request...")
cr = post_json(f"https://api.gitbook.com/v1/spaces/{SPACE_ID}/change-requests", {"subject": "Import docs markdown content"})
cr_id = cr["id"]
print("Change request ID:", cr_id)

summary_path = os.path.join(DOCS_DIR, "SUMMARY.md")
with open(summary_path, "r") as f:
    summary_lines = f.readlines()

changes = []
for line in summary_lines:
    if "* [" in line and "](" in line:
        title = line.split("[")[1].split("]")[0]
        rel_path = line.split("(")[1].split(")")[0]
        file_path = os.path.join(DOCS_DIR, rel_path)
        
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                content = f.read()
            doc_node = markdown_to_gitbook_document(content)
            
            changes.append({
                "action": "add",
                "type": "document",
                "title": title,
                "document": doc_node
            })

print(f"Submitting batch change request with {len(changes)} pages...")
batch_res = post_json(f"https://api.gitbook.com/v1/spaces/{SPACE_ID}/change-requests/{cr_id}/content", {"changes": changes})
print("Batch update submitted!")

print("Merging change request...")
merge_res = post_json(f"https://api.gitbook.com/v1/spaces/{SPACE_ID}/change-requests/{cr_id}/merge", {})
print("Merge complete:", merge_res)
