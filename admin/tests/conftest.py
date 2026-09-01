"""Admin 集成测试：复用 backend 的 DB fixture 约定。"""

from __future__ import annotations

import os
import sys
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

ROOT = Path(__file__).resolve().parents[2]
BACKEND_TESTS = ROOT / "backend" / "tests"
if str(BACKEND_TESTS) not in sys.path:
    sys.path.insert(0, str(BACKEND_TESTS))

os.environ.setdefault("COCO_ENVIRONMENT", "test")


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line("markers", "integration: needs PostgreSQL via COCO_DATABASE_URL")


def _resolve_database_url() -> str | None:
    raw = (os.environ.get("COCO_DATABASE_URL") or "").strip()
    if raw:
        return raw
    from coco.config import get_settings

    get_settings.cache_clear()
    url = get_settings().database_url.strip()
    return url or None


@pytest.fixture(scope="session")
def require_test_db() -> str:
    url = _resolve_database_url()
    if not url:
        pytest.skip("未设置 COCO_DATABASE_URL，跳过集成测试")
    return url


@pytest_asyncio.fixture
async def db_engine(require_test_db: str):
    from alembic.config import Config

    from alembic import command

    backend_dir = ROOT / "backend"
    engine = create_async_engine(require_test_db, pool_pre_ping=True)
    cfg = Config(str(backend_dir / "alembic.ini"))
    cfg.set_main_option("sqlalchemy.url", require_test_db)
    os.environ["COCO_DATABASE_URL"] = require_test_db
    command.upgrade(cfg, "head")
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def session_factory(db_engine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(bind=db_engine, expire_on_commit=False, class_=AsyncSession)
