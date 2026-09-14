import importlib
import os
import stat
from pathlib import Path

from fastapi.testclient import TestClient


def load_app(tmp_path: Path):
    controller = Path(__file__).with_name("fake_controller.py")
    controller.chmod(controller.stat().st_mode | stat.S_IXUSR)
    os.environ["LTX_CONTROL_CMD"] = str(controller)
    os.environ["LTX_BRIDGE_TOKEN"] = "test-token"
    os.environ["LTX_BRIDGE_STATE_DIR"] = str(tmp_path)
    import app as bridge
    importlib.reload(bridge)
    return TestClient(bridge.app)


def auth():
    return {"Authorization": "Bearer test-token"}


def test_health_reports_publish_lock(tmp_path):
    client = load_app(tmp_path)
    data = client.get("/health").json()
    assert data["publishing_locked"] is True
    assert data["controller_configured"] is True


def test_start_forces_publish_false(tmp_path):
    client = load_app(tmp_path)
    r = client.post(
        "/v1/production/start",
        headers=auth(),
        json={
            "show": "Hip Hop What If",
            "episode": "Test Episode",
            "auto_fix": True,
            "publish": False,
            "shorts_count": 5,
        },
    )
    assert r.status_code == 200
    data = r.json()
    assert data["publish_locked"] is True
    assert data["status"] == "running"


def test_start_rejects_publish_true(tmp_path):
    client = load_app(tmp_path)
    r = client.post(
        "/v1/production/start",
        headers=auth(),
        json={"show": "Any", "episode": "Any", "publish": True},
    )
    assert r.status_code == 409


def test_publish_endpoint_is_disabled(tmp_path):
    client = load_app(tmp_path)
    r = client.post("/v1/publish")
    assert r.status_code == 423


def test_qc_can_move_job_ready_for_review(tmp_path):
    client = load_app(tmp_path)
    start = client.post(
        "/v1/production/start",
        headers=auth(),
        json={"show": "The Case Against", "episode": "Rod Wave"},
    ).json()
    r = client.post(
        f"/v1/production/{start['job_id']}/qc",
        headers=auth(),
        json={"auto_fix": True},
    )
    assert r.status_code == 200
    assert r.json()["status"] == "ready_for_review"
