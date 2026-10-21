#!/usr/bin/python3
"""只模拟额度接口；不访问账户或网络。"""
import json
import os
import sys

for line in sys.stdin:
    request = json.loads(line)
    method = request["method"]
    if method == "initialize":
        response = {"id": request["id"], "result": {"userAgent": "test"}}
    elif method == "initialized":
        continue
    elif method == "account/rateLimits/read":
        if os.environ.get("QUOTA_TEST_ERROR") == "1":
            response = {"id": request["id"], "error": {"code": -32000, "message": "PRIVATE_ERROR_MARKER"}}
        else:
            response = {"id": request["id"], "result": {"rateLimits": {"limitId": "codex", "primary": {
                "usedPercent": 27, "windowDurationMins": 300, "resetsAt": 1800000000
            }}}}
    else:
        raise RuntimeError("Unexpected method: " + method)
    encoded = json.dumps(response) + "\n"
    # 拆开一次写入，验证客户端能处理分段的 JSON 行。
    sys.stdout.write(encoded[:11])
    sys.stdout.flush()
    sys.stdout.write(encoded[11:])
    sys.stdout.flush()
