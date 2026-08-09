"""Alembic 环境：使用异步引擎，版本表落在 coco schema。"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from coco.config import get_settings
from coco.models import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata
settings = get_settings()
config.set_main_option("sqlalchemy.url", settings.database_url)


def include_name(name: str | None, type_: str, parent_names: dict) -> bool:
    # 只管理 coco schema，绝不触碰 public 里的旧表
    if type_ == "schema":
        return name == "coco"
    return True


def include_object(object_, name: str | None, type_: str, reflected: bool, compare_to) -> bool:
    schema = getattr(object_, "schema", None)
    if type_ == "table" and schema not in {None, "coco"}:
        return False
    if reflected and schema not in {None, "coco"}:
        return False
    return True


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_schemas=True,
        include_name=include_name,
        include_object=include_object,
        version_table_schema="coco",
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    connection.exec_driver_sql("CREATE SCHEMA IF NOT EXISTS coco")
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_schemas=True,
        include_name=include_name,
        include_object=include_object,
        version_table_schema="coco",
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    # begin() 确保迁移在连接关闭前真正提交
    async with connectable.begin() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
