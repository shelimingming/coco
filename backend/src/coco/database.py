"""异步数据库引擎与会话依赖。"""

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from coco.config import Settings, get_settings

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def init_database(settings: Settings | None = None) -> async_sessionmaker[AsyncSession]:
    global _engine, _session_factory
    resolved = settings or get_settings()
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
    assert _session_factory is not None
    return _session_factory


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    if _session_factory is None:
        return init_database()
    return _session_factory


async def get_session() -> AsyncIterator[AsyncSession]:
    factory = get_session_factory()
    async with factory() as session:
        yield session


async def dispose_database() -> None:
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _session_factory = None
