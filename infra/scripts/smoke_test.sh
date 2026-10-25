#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

compose=(docker compose --env-file infra/.env -f infra/docker-compose.yml)
result_file="$(mktemp)"

cleanup() {
    if [[ -s "$result_file" ]]; then
        read -r user_id admin_user_id campaign_id ad_id creative_id delivery_id site_id placement_id < <(
            python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("user_id", 0), d.get("admin_user_id", 0), d.get("campaign_id", 0), d.get("ad_id", 0), d.get("creative_id", 0), d.get("delivery_id", ""), d.get("site_id", 0), d.get("placement_id", 0))' "$result_file"
        )

        "${compose[@]}" exec -T mysql sh -ec \
            "mysql --protocol=tcp -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \"\$MYSQL_DATABASE\" -e '
                DELETE FROM delivery_outbox WHERE delivery_id = \"${delivery_id}\";
                DELETE FROM ad_deliveries WHERE id = \"${delivery_id}\";
                DELETE FROM creatives WHERE id = ${creative_id};
                DELETE FROM ads WHERE id = ${ad_id};
                DELETE FROM campaigns WHERE id = ${campaign_id};
                DELETE FROM placements WHERE id = ${placement_id};
                DELETE FROM sites WHERE id = ${site_id};
                DELETE FROM transactions WHERE user_id = ${user_id};
                DELETE FROM balances WHERE user_id = ${user_id};
                DELETE FROM balances WHERE user_id = ${admin_user_id};
                DELETE FROM users WHERE id = ${user_id};
                DELETE FROM users WHERE id = ${admin_user_id};
            '" >/dev/null 2>&1 || true

        "${compose[@]}" exec -T clickhouse sh -ec \
            "clickhouse-client --user \"\$CLICKHOUSE_USER\" --password \"\$CLICKHOUSE_PASSWORD\" --database \"\$CLICKHOUSE_DB\" --multiquery --query 'ALTER TABLE ads_stats DELETE WHERE ad_id = ${ad_id}; ALTER TABLE delivery_stats DELETE WHERE ad_id = ${ad_id}'" \
            >/dev/null 2>&1 || true
    fi
    rm -f "$result_file"
}
trap cleanup EXIT

wait_for_url() {
    local name="$1"
    local url="$2"
    local attempts=30

    until curl --fail --silent --show-error "$url" >/dev/null; do
        attempts=$((attempts - 1))
        if [[ "$attempts" -eq 0 ]]; then
            echo "ERROR: $name did not become ready: $url" >&2
            return 1
        fi
        sleep 2
    done
    echo "OK: $name"
}

wait_for_url "ads-api" "http://127.0.0.1:8080/health"
wait_for_url "auth-api" "http://127.0.0.1:8000/health"
wait_for_url "analytics-api" "http://127.0.0.1:8100/health"
wait_for_url "admin-panel" "http://127.0.0.1:8001/health"
wait_for_url "Grafana" "http://127.0.0.1:3000/api/health"
wait_for_url "Prometheus" "http://127.0.0.1:9090/-/healthy"
wait_for_url "ads-api metrics" "http://127.0.0.1:8080/metrics"
wait_for_url "auth-api metrics" "http://127.0.0.1:8000/metrics"
wait_for_url "analytics-api metrics" "http://127.0.0.1:8100/metrics"
wait_for_url "MySQL exporter" "http://127.0.0.1:9104/metrics"
curl --fail --silent http://127.0.0.1:9104/metrics | grep -q '^mysql_up 1$'
echo "OK: MySQL exporter is connected"

SMOKE_RESULT_FILE="$result_file" python3 - <<'PY'
import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid


def request(method, url, payload=None, expected=(200,), token=None):
    body = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status not in expected:
                raise RuntimeError(f"{method} {url}: HTTP {response.status}")
            raw = response.read()
            return json.loads(raw.decode()) if raw else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        raise RuntimeError(f"{method} {url}: HTTP {exc.code}: {detail}") from exc


def upload(url, fields, file_name, content, content_type, method="POST"):
    boundary = f"smoke-{uuid.uuid4().hex}"
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
        f'Content-Disposition: form-data; name="file"; filename="{file_name}"\r\n'.encode(),
        f"Content-Type: {content_type}\r\n\r\n".encode(),
        content,
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(
        url,
        data=b"".join(chunks),
        method=method,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.loads(response.read().decode())


result_path = os.environ["SMOKE_RESULT_FILE"]
email = f"smoke-{uuid.uuid4().hex}@example.com"
password = "SmokeTest_2026!"

user = request(
    "POST",
    "http://127.0.0.1:8000/auth/register",
    {"email": email, "password": password},
    expected=(201,),
)
result = {"user_id": int(user["id"])}
with open(result_path, "w") as output:
    json.dump(result, output)

admin_email = f"smoke-admin-{uuid.uuid4().hex}@example.com"
admin = request(
    "POST",
    "http://127.0.0.1:8000/auth/register",
    {"email": admin_email, "password": password},
    expected=(201,),
)
result["admin_user_id"] = int(admin["id"])
with open(result_path, "w") as output:
    json.dump(result, output)
subprocess.run(
    [
        "docker",
        "compose",
        "--env-file",
        "infra/.env",
        "-f",
        "infra/docker-compose.yml",
        "exec",
        "-T",
        "mysql",
        "sh",
        "-ec",
        (
            'mysql --protocol=tcp -uroot -p"$MYSQL_ROOT_PASSWORD" '
            '"$MYSQL_DATABASE" -e '
            f"'UPDATE users SET role = \"admin\" WHERE id = {result['admin_user_id']}'"
        ),
    ],
    check=True,
    stdout=subprocess.DEVNULL,
)
admin_token = request(
    "POST",
    "http://127.0.0.1:8000/auth/login",
    {"email": admin_email, "password": password},
)["access_token"]

token = request(
    "POST",
    "http://127.0.0.1:8000/auth/login",
    {"email": email, "password": password},
)
access_token = token["access_token"]
assert access_token

current_user = request(
    "GET",
    "http://127.0.0.1:8000/auth/me",
    token=access_token,
)
assert current_user == {
    "id": result["user_id"],
    "email": email,
    "role": "user",
}

request(
    "POST",
    "http://127.0.0.1:8000/billing/deposit",
    {"user_id": result["user_id"], "amount": 100, "description": "smoke test"},
)
balance = request(
    "GET", f"http://127.0.0.1:8000/billing/balance/{result['user_id']}"
)
assert balance["balance"] == 100.0

campaign = request(
    "POST",
    "http://127.0.0.1:8080/campaigns",
    {
        "user_id": result["user_id"],
        "name": "smoke campaign",
        "status": "active",
        "budget": {"total": 10, "daily_limit": 2},
        "schedule": {
            "days_of_week": [],
            "start_hour": 0,
            "end_hour": 24,
        },
    },
    expected=(201,),
)
result["campaign_id"] = int(campaign["id"])
assert campaign["budget"] == {
    "total": 10,
    "daily_limit": 2,
    "spent_total": 0,
    "spent_today": 0,
}
assert campaign["schedule"]["timezone"] == "UTC"
with open(result_path, "w") as output:
    json.dump(result, output)

campaigns = request(
    "GET",
    f"http://127.0.0.1:8080/campaigns?user_id={result['user_id']}",
    token=access_token,
)
assert [item["id"] for item in campaigns] == [result["campaign_id"]]

formats = request("GET", "http://127.0.0.1:8080/formats", token=access_token)
ad_format = next(item for item in formats if item["code"] == "native_feed")
result["format_id"] = int(ad_format["id"])

site = request(
    "POST",
    "http://127.0.0.1:8080/sites",
    {
        "user_id": result["user_id"],
        "name": "smoke site",
        "domain": f"smoke-{uuid.uuid4().hex}.example.com",
        "status": "active",
    },
    expected=(201,),
)
result["site_id"] = int(site["id"])

placement = request(
    "POST",
    "http://127.0.0.1:8080/placements",
    {
        "site_id": result["site_id"],
        "format_id": result["format_id"],
        "name": "smoke feed",
        "status": "active",
    },
    expected=(201,),
)
result["placement_id"] = int(placement["id"])
result["placement_code"] = placement["code"]
with open(result_path, "w") as output:
    json.dump(result, output)

sites = request(
    "GET",
    f"http://127.0.0.1:8080/sites?user_id={result['user_id']}",
    token=access_token,
)
placements = request(
    "GET",
    f"http://127.0.0.1:8080/placements?site_id={result['site_id']}",
    token=access_token,
)
assert [item["id"] for item in sites] == [result["site_id"]]
assert [item["id"] for item in placements] == [result["placement_id"]]

ad = request(
    "POST",
    "http://127.0.0.1:8080/ads",
    {
        "campaign_id": result["campaign_id"],
        "title": "smoke ad",
        "status": "active",
        "placement": "feed",
        "destination_url": "https://example.com/offer",
        "weight": 10,
        "bid_cpm": 12.5,
        "placement_id": result["placement_id"],
        "targeting": {
            "audience": {
                "min_age": 18,
                "max_age": 35,
                "genders": ["female"],
                "interests": ["travel", "technology"],
            },
            "geography": {
                "countries": ["RU"],
                "regions": ["moscow"],
                "cities": ["moscow"],
            },
            "device": {
                "types": ["mobile"],
                "operating_systems": ["android"],
            },
        },
    },
    expected=(201,),
)
result["ad_id"] = int(ad["id"])
with open(result_path, "w") as output:
    json.dump(result, output)

ads = request(
    "GET",
    f"http://127.0.0.1:8080/ads?campaign_id={result['campaign_id']}",
    token=access_token,
)
assert [item["id"] for item in ads] == [result["ad_id"]]

image_bytes = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)
creative = upload(
    "http://127.0.0.1:8080/creatives/upload",
    {"ad_id": result["ad_id"], "content": "smoke creative"},
    "smoke.png",
    image_bytes,
    "image/png",
)
assert creative["media"]["type"] == "image"
assert creative["media"]["mime_type"] == "image/png"
assert creative["media"]["file_name"] == "smoke.png"
assert creative["moderation_status"] == "draft"
with urllib.request.urlopen(
    f"http://127.0.0.1:8080{creative['media']['url']}", timeout=10
) as media_response:
    assert media_response.read() == image_bytes
result["creative_id"] = int(creative["id"])
with open(result_path, "w") as output:
    json.dump(result, output)

creatives = request(
    "GET",
    f"http://127.0.0.1:8080/creatives?ad_id={result['ad_id']}",
    token=access_token,
)
assert [item["id"] for item in creatives] == [result["creative_id"]]
assert creatives[0]["media"]["url"] == creative["media"]["url"]


def delivery_payload(request_id):
    return {
        "request_id": request_id,
        "placement_code": result["placement_code"],
        "visitor_id": "smoke-visitor",
        "audience": {
            "age": 27,
            "gender": "female",
            "interests": ["travel"],
        },
        "geography": {
            "country": "RU",
            "region": "Moscow",
            "city": "Moscow",
        },
        "device": {"type": "mobile", "operating_system": "android"},
    }


assert request(
    "POST",
    "http://127.0.0.1:8080/delivery/select",
    delivery_payload(str(uuid.uuid4())),
    expected=(204,),
) is None

try:
    request(
        "GET",
        "http://127.0.0.1:8080/moderation/creatives?status=pending",
        token=access_token,
    )
except RuntimeError as exc:
    assert "HTTP 403" in str(exc)
else:
    raise RuntimeError("regular user accessed moderation queue")

submitted = request(
    "POST",
    f"http://127.0.0.1:8080/creatives/{result['creative_id']}/submit",
    token=access_token,
)
assert submitted["moderation_status"] == "pending"
queue = request(
    "GET",
    "http://127.0.0.1:8080/moderation/creatives?status=pending",
    token=admin_token,
)
queued_creative = next(
    item for item in queue if item["id"] == result["creative_id"]
)
assert queued_creative["campaign_name"] == campaign["name"]
approved = request(
    "POST",
    f"http://127.0.0.1:8080/moderation/creatives/{result['creative_id']}/review",
    {"decision": "approved", "reason": ""},
    token=admin_token,
)
assert approved["moderation_status"] == "approved"

request(
    "PUT",
    f"http://127.0.0.1:8080/ads/{result['ad_id']}",
    {
        "campaign_id": result["campaign_id"],
        "title": "smoke ad updated",
        "status": "active",
        "placement": "feed",
        "destination_url": "https://example.com/offer",
        "weight": 10,
        "bid_cpm": 12.5,
        "placement_id": result["placement_id"],
        "targeting": {
            "audience": {
                "min_age": 18,
                "max_age": 35,
                "genders": ["female"],
                "interests": ["travel", "technology"],
            },
            "geography": {
                "countries": ["RU"],
                "regions": ["moscow"],
                "cities": ["moscow"],
            },
            "device": {
                "types": ["mobile"],
                "operating_systems": ["android"],
            },
        },
    },
)

delivery_request_id = str(uuid.uuid4())
delivery = request(
    "POST",
    "http://127.0.0.1:8080/delivery/select",
    delivery_payload(delivery_request_id),
)
assert delivery["delivery_id"] == delivery_request_id
assert delivery["campaign_id"] == result["campaign_id"]
assert delivery["ad_id"] == result["ad_id"]
assert delivery["creative_id"] == result["creative_id"]
assert delivery["media"] == creative["media"]
assert delivery["site_id"] == result["site_id"]
assert delivery["placement_id"] == result["placement_id"]
assert delivery["format_id"] == result["format_id"]
assert delivery["placement_code"] == result["placement_code"]
assert delivery["format_code"] == "native_feed"
assert delivery["bid_cpm"] == 12.5
assert abs(delivery["cost"] - 0.0125) < 0.000001
assert delivery["audience"] == {
    "age": 27,
    "gender": "female",
    "interests": ["travel"],
}
assert delivery["geography"] == {
    "country": "RU",
    "region": "moscow",
    "city": "moscow",
}
assert delivery["device"] == {
    "type": "mobile",
    "operating_system": "android",
}
assert delivery["destination_url"] == "https://example.com/offer"
assert delivery["impression_url"] == f"http://127.0.0.1:8080/delivery/{delivery_request_id}/impression"
assert delivery["click_url"] == f"http://127.0.0.1:8080/delivery/{delivery_request_id}/click"
assert delivery["conversion_url"] == f"http://127.0.0.1:8080/delivery/{delivery_request_id}/conversion"
result["delivery_id"] = delivery_request_id
with open(result_path, "w") as output:
    json.dump(result, output)

same_delivery = request(
    "POST",
    "http://127.0.0.1:8080/delivery/select",
    {
        "request_id": delivery_request_id,
        "placement_code": result["placement_code"],
        "visitor_id": "smoke-visitor",
        "audience": {
            "age": 27,
            "gender": "female",
            "interests": ["travel"],
        },
        "geography": {
            "country": "RU",
            "region": "Moscow",
            "city": "Moscow",
        },
        "device": {"type": "mobile", "operating_system": "android"},
    },
)
assert same_delivery["delivery_id"] == delivery["delivery_id"]
campaign_after_delivery = request(
    "GET", f"http://127.0.0.1:8080/campaigns/{result['campaign_id']}"
)
assert abs(campaign_after_delivery["budget"]["spent_total"] - 0.0125) < 0.000001
assert abs(campaign_after_delivery["budget"]["spent_today"] - 0.0125) < 0.000001

first_impression = request(
    "POST", f"http://127.0.0.1:8080/delivery/{delivery_request_id}/impression"
)
second_impression = request(
    "POST", f"http://127.0.0.1:8080/delivery/{delivery_request_id}/impression"
)
assert first_impression["event_type"] == "ad_impression"
assert first_impression["recorded"] is True
assert second_impression["recorded"] is False
assert second_impression["event_id"] == first_impression["event_id"]

first_click = request(
    "POST", f"http://127.0.0.1:8080/delivery/{delivery_request_id}/click"
)
second_click = request(
    "POST", f"http://127.0.0.1:8080/delivery/{delivery_request_id}/click"
)
assert first_click["clicked"] is True
assert second_click["clicked"] is True
assert first_click["event_type"] == "ad_click"
assert first_click["recorded"] is True
assert second_click["recorded"] is False

conversion_event_id = f"smoke-{uuid.uuid4()}"
conversion_payload = {
    "event_id": conversion_event_id,
    "conversion_type": "purchase",
    "value": 2499.5,
    "currency": "RUB",
}
first_conversion = request(
    "POST",
    f"http://127.0.0.1:8080/delivery/{delivery_request_id}/conversion",
    conversion_payload,
)
second_conversion = request(
    "POST",
    f"http://127.0.0.1:8080/delivery/{delivery_request_id}/conversion",
    conversion_payload,
)
assert first_conversion["event_type"] == "ad_conversion"
assert first_conversion["recorded"] is True
assert first_conversion["conversion_value"] == 2499.5
assert second_conversion["recorded"] is False
assert second_conversion["event_id"] == conversion_event_id


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


redirect_opener = urllib.request.build_opener(NoRedirect)
try:
    redirect_opener.open(
        f"http://127.0.0.1:8080/delivery/{delivery_request_id}/click",
        timeout=10,
    )
except urllib.error.HTTPError as exc:
    assert exc.code == 302
    assert exc.headers["Location"] == "https://example.com/offer"
else:
    raise RuntimeError("click endpoint did not redirect")

for _ in range(30):
    ad_rows = request(
        "GET", f"http://127.0.0.1:8100/ads?ad_id={result['ad_id']}"
    )
    campaign_rows = request(
        "GET",
        f"http://127.0.0.1:8100/campaigns?campaign_id={result['campaign_id']}",
    )
    creative_rows = request(
        "GET",
        f"http://127.0.0.1:8100/creatives?creative_id={result['creative_id']}",
    )
    if (
        sum(row["total_impressions"] for row in ad_rows) == 1
        and sum(row["total_clicks"] for row in ad_rows) == 1
        and sum(row["total_conversions"] for row in ad_rows) == 1
        and abs(sum(row["total_conversion_value"] for row in ad_rows) - 2499.5) < 0.000001
        and sum(row["total_impressions"] for row in campaign_rows) == 1
        and sum(row["total_clicks"] for row in campaign_rows) == 1
        and sum(row["total_conversions"] for row in campaign_rows) == 1
        and sum(row["total_impressions"] for row in creative_rows) == 1
        and sum(row["total_clicks"] for row in creative_rows) == 1
        and sum(row["total_conversions"] for row in creative_rows) == 1
        and abs(sum(row["total_cost"] for row in ad_rows) - 0.0125) < 0.000001
    ):
        break
    time.sleep(1)
else:
    raise RuntimeError("delivery impression/click/conversion events did not reach ClickHouse")

request("DELETE", f"http://127.0.0.1:8080/creatives/{result['creative_id']}")
request("DELETE", f"http://127.0.0.1:8080/ads/{result['ad_id']}")
request("DELETE", f"http://127.0.0.1:8080/campaigns/{result['campaign_id']}")
request("DELETE", f"http://127.0.0.1:8080/placements/{result['placement_id']}")
request("DELETE", f"http://127.0.0.1:8080/sites/{result['site_id']}")

try:
    request("GET", f"http://127.0.0.1:8080/ads/{result['ad_id']}")
except RuntimeError as exc:
    if "HTTP 404" not in str(exc):
        raise
else:
    raise RuntimeError("Deleted ad is still available")

print("OK: end-to-end business flow")
PY

python3 - <<'PY'
import json
import time
import urllib.request

url = "http://127.0.0.1:9090/api/v1/targets"
for _ in range(20):
    with urllib.request.urlopen(url, timeout=5) as response:
        payload = json.load(response)
    targets = payload["data"]["activeTargets"]
    health = {target["labels"].get("job"): target["health"] for target in targets}
    if health and all(state == "up" for state in health.values()):
        print("OK: all Prometheus targets are up")
        break
    time.sleep(2)
else:
    raise SystemExit(f"ERROR: unhealthy Prometheus targets: {health}")
PY

"${compose[@]}" exec -T redis redis-cli ping | grep -q PONG
"${compose[@]}" exec -T rabbitmq rabbitmq-diagnostics -q ping
"${compose[@]}" exec -T mysql sh -ec \
    'mysql --protocol=tcp -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null'
"${compose[@]}" exec -T clickhouse sh -ec \
    'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "SELECT 1" >/dev/null'

echo "All smoke checks passed."
