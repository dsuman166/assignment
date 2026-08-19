import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import app as app_module  # noqa: E402


def test_index_returns_message():
    client = app_module.app.test_client()
    resp = client.get("/")
    assert resp.status_code == 200
    assert "message" in resp.get_json()


def test_health_ok():
    client = app_module.app.test_client()
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"
