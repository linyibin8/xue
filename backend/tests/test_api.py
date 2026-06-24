import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ["XUE_DATA_DIR"] = "test-data"
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import llm  # noqa: E402
from app.main import app  # noqa: E402


async def fake_analyze(settings, prompt, image_paths):
    return "第 1 页，第 1 题\n\n解题思路：先审题，再列式。"


def test_single_upload(monkeypatch, tmp_path):
    os.environ["XUE_DATA_DIR"] = str(tmp_path)
    monkeypatch.setattr(llm, "analyze_images", fake_analyze)
    with TestClient(app) as client:
        health = client.get("/health")
        assert health.status_code == 200
        response = client.post(
            "/api/solve-single",
            files={"image": ("question.jpg", b"\xff\xd8\xff\xd9", "image/jpeg")},
            data={"device_id": "test-phone", "page_hint": "1", "question_hint": "1"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["session"]["mode"] == "single"
        assert body["analyses"][0]["status"] == "done"
        assert "解题思路" in body["analyses"][0]["content"]


def test_burst_batch(monkeypatch, tmp_path):
    os.environ["XUE_DATA_DIR"] = str(tmp_path)
    monkeypatch.setattr(llm, "analyze_images", fake_analyze)
    with TestClient(app) as client:
        session_id = client.post("/api/sessions", data={"device_id": "test-phone"}).json()["session_id"]
        response = client.post(
            f"/api/sessions/{session_id}/batches",
            files=[
                ("images", ("a.jpg", b"\xff\xd8\xff\xd9", "image/jpeg")),
                ("images", ("b.jpg", b"\xff\xd8\xff\xd9", "image/jpeg")),
            ],
            data={"environment": "固定机位，桌面试卷"},
        )
        assert response.status_code == 200
        detail = client.get(f"/api/sessions/{session_id}").json()
        assert len(detail["images"]) == 2
        assert detail["analyses"][0]["scope"] == "batch"
