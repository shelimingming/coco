"""管理后台独立异步引擎（与用户端进程隔离，共用同一 PostgreSQL）。"""

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from coco_admin.config import AdminSettings, get_admin_settings

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def init_admin_database(
    settings: AdminSettings | None = None,
) -> tuple[AsyncEngine, async_sessionmaker[AsyncSession]]:
    global _engine, _session_factory
    resolved = settings or get_admin_settings()
    if _engine is None:
        _engine = create_async_engine(
            resolved.database_url,
            pool_pre_ping=True,
            pool_recycle=1800,
        )
        _session_factory = async_sessionmaker(
            bind=_engine,
            expire_on_commit=False,
            class_=AsyncSession,
        )
    assert _engine is not None
    assert _session_factory is not None
    return _engine, _session_factory


def get_engine() -> AsyncEngine:
    if _engine is None:
        engine, _ = init_admin_database()
        return engine
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    if _session_factory is None:
        _, factory = init_admin_database()
        return factory
    return _session_factory


async def get_session() -> AsyncIterator[AsyncSession]:
    factory = get_session_factory()
    async with factory() as session:
        yield session


async def dispose_admin_database() -> None:
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _session_factory = None
