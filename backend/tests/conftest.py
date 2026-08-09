"""集成测试 fixture：依赖 COCO_TEST_DATABASE_URL，缺失则跳过。"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

# 在导入 app 前强制测试环境，避免启动调度器
os.environ.setdefault("COCO_ENVIRONMENT", "test")

TEST_DATABASE_URL = os.environ.get("COCO_TEST_DATABASE_URL")


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line("markers", "integration: needs PostgreSQL test database")


@pytest.fixture(scope="session")
def require_test_db() -> str:
    if not TEST_DATABASE_URL:
        pytest.skip("未设置 COCO_TEST_DATABASE_URL，跳过集成测试")
    return TEST_DATABASE_URL


@pytest_asyncio.fixture
async def db_engine(require_test_db: str):
    from alembic.config import Config

    from alembic import command

    engine = create_async_engine(require_test_db, pool_pre_ping=True)
    # 跑迁移到最新
    cfg = Config("alembic.ini")
    cfg.set_main_option("sqlalchemy.url", require_test_db)
    # alembic 同步路径：临时用环境变量覆盖
    os.environ["COCO_DATABASE_URL"] = require_test_db
    command.upgrade(cfg, "head")
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def session_factory(db_engine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(bind=db_engine, expire_on_commit=False, class_=AsyncSession)


@pytest_asyncio.fixture
async def client(
    require_test_db: str,
    monkeypatch: pytest.MonkeyPatch,
) -> AsyncIterator[AsyncClient]:
    monkeypatch.setenv("COCO_ENVIRONMENT", "test")
    monkeypatch.setenv("COCO_DATABASE_URL", require_test_db)
    monkeypatch.setenv("COCO_SMS_PROVIDER", "dev")

    from coco.config import get_settings
    from coco.database import dispose_database, init_database
    from coco.main import create_app

    get_settings.cache_clear()
    settings = get_settings()
    init_database(settings)
    app = create_app(settings)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    await dispose_database()
    get_settings.cache_clear()
