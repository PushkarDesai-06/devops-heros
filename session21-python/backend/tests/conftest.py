"""Shared pytest setup.

Tests run against a throw-away SQLite file instead of PostgreSQL, so they never
touch a real database. DATABASE_URL must be set *before* the app is imported,
because app.config builds its Settings object at import time.

FastAPI only runs the startup hook (which creates the tables) when TestClient is
used as a context manager, so the schema is created here explicitly.
"""
import os

os.environ["DATABASE_URL"] = "sqlite:///./test.db"

import pytest  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app import models  # noqa: E402,F401  (registers the Task table on Base.metadata)


@pytest.fixture(scope="session", autouse=True)
def database_schema():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)
    engine.dispose()
    if os.path.exists("test.db"):
        os.remove("test.db")
