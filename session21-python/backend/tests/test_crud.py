"""CRUD, validation and stats tests for /api/tasks (schema comes from conftest.py)."""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _create(**overrides):
    payload = {"title": "Write Helm chart", "priority": "MEDIUM", "assignee": "Student"}
    payload.update(overrides)
    response = client.post("/api/tasks", json=payload)
    assert response.status_code == 201
    return response.json()


def test_list_tasks_returns_newest_first():
    first = _create(title="First task")
    second = _create(title="Second task")
    ids = [t["id"] for t in client.get("/api/tasks").json()]
    assert ids.index(second["id"]) < ids.index(first["id"])


def test_get_task_by_id_and_404():
    task = _create(title="Configure ingress")
    assert client.get(f"/api/tasks/{task['id']}").json()["title"] == "Configure ingress"
    missing = client.get("/api/tasks/999999")
    assert missing.status_code == 404
    assert missing.json() == {"detail": "Task not found"}


def test_update_task_status():
    task = _create(title="Add HPA")
    response = client.put(f"/api/tasks/{task['id']}", json={"status": "IN_PROGRESS"})
    assert response.status_code == 200
    assert response.json()["status"] == "IN_PROGRESS"
    assert response.json()["title"] == "Add HPA"  # untouched fields are kept


def test_delete_task():
    task = _create(title="Temporary task")
    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_invalid_priority_and_empty_title_are_rejected():
    assert client.post("/api/tasks", json={"title": "x", "priority": "URGENT"}).status_code == 422
    assert client.post("/api/tasks", json={"title": ""}).status_code == 422


def test_stats_counts_by_status():
    before = client.get("/api/tasks/stats").json()
    _create(title="Done task", status="DONE")
    after = client.get("/api/tasks/stats").json()
    assert after["total"] == before["total"] + 1
    assert after["done"] == before["done"] + 1
    assert set(after) == {"total", "todo", "inProgress", "done"}


def test_metrics_endpoint_exposes_prometheus_format():
    client.get("/health")
    body = client.get("/metrics").text
    assert "http_requests_total" in body
