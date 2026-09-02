"""只读查询 Mem0 pgvector collection，按用户分组。

不走 Mem0 SDK：运营页不依赖百炼 Key，也不受 get_all 默认 20 条限制。
"""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from coco.config import get_settings
from coco.models.user import User
from sqlalchemy import or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

CST = ZoneInfo("Asia/Shanghai")
DEFAULT_COLLECTION = "coco_memories"
# 防止 collection 名被拼进 SQL 时注入
_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# 单次最多拉这么多，避免运营页一次扫爆向量表
ROW_CAP = 5000
_SKIP_PAYLOAD_TYPES = {"user_identity"}
_ROLE_LABELS = {"parent": "父母", "child": "子女"}


def quote_ident(name: str) -> str:
    """校验并双引号包裹 PostgreSQL 标识符。"""
    if not _IDENT_RE.fullmatch(name):
        raise ValueError(f"非法标识符: {name}")
    return '"' + name.replace('"', '""') + '"'


def collection_name() -> str:
    name = (get_settings().mem0_collection_name or DEFAULT_COLLECTION).strip()
    return name if _IDENT_RE.fullmatch(name) else DEFAULT_COLLECTION


def parse_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value
    text_value = str(value).strip()
    if not text_value:
        return None
    try:
        parsed = datetime.fromisoformat(text_value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed


def format_cst(value: datetime | None) -> str:
    if value is None:
        return ""
    return value.astimezone(CST).strftime("%Y-%m-%d %H:%M")


def parse_payload(memory_id: str, payload: Any) -> dict[str, Any] | None:
    """把 pgvector payload 收成运营页条目；跳过遥测/空正文。"""
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except json.JSONDecodeError:
            return None
    if not isinstance(payload, dict):
        return None
    if str(payload.get("type") or "").strip() in _SKIP_PAYLOAD_TYPES:
        return None
    content = str(payload.get("data") or payload.get("memory") or payload.get("text") or "").strip()
    if not memory_id or not content:
        return None
    user_raw = payload.get("user_id")
    user_id = str(user_raw).strip() if user_raw is not None else ""
    created_at = parse_datetime(payload.get("created_at"))
    updated_at = parse_datetime(payload.get("updated_at"))
    return {
        "id": memory_id,
        "content": content,
        "user_id": user_id or None,
        "created_at": created_at,
        "updated_at": updated_at,
        "created_at_label": format_cst(created_at),
        "updated_at_label": format_cst(updated_at),
    }


async def find_collection_schema(session: AsyncSession, name: str) -> str | None:
    """优先 coco schema（与 backend search_path 一致），其次 public。"""
    result = await session.execute(
        text(
            """
            SELECT table_schema
            FROM information_schema.tables
            WHERE table_name = :name
              AND table_schema IN ('coco', 'public')
            ORDER BY CASE table_schema WHEN 'coco' THEN 0 ELSE 1 END
            LIMIT 1
            """
        ),
        {"name": name},
    )
    row = result.first()
    return str(row[0]) if row is not None else None


def group_memory_items(
    items: list[dict[str, Any]],
    users: dict[str, User],
    *,
    q: str = "",
) -> list[dict[str, Any]]:
    """按 user_id 分组；q 命中用户则保留全部记忆，否则只留正文匹配的条。"""
    grouped: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for item in items:
        key = item["user_id"] or "unknown"
        if key not in grouped:
            user = users.get(key) if item["user_id"] else None
            grouped[key] = {
                "user_id": item["user_id"],
                "user": user,
                "display_name": user.display_name if user is not None else "未知用户",
                "role": user.role if user is not None else "",
                "role_label": _ROLE_LABELS.get(user.role, user.role) if user is not None else "—",
                "phone_masked": user.phone_masked if user is not None else "—",
                "memories": [],
            }
            order.append(key)
        grouped[key]["memories"].append(item)

    groups = []
    fallback = datetime.min.replace(tzinfo=UTC)
    for key in order:
        bucket = grouped[key]
        bucket["memories"].sort(
            key=lambda m: m["updated_at"] or m["created_at"] or fallback,
            reverse=True,
        )
        bucket["count"] = len(bucket["memories"])
        groups.append(bucket)

    needle = q.strip()
    if needle:
        filtered: list[dict[str, Any]] = []
        for group in groups:
            matched = _match_q(group, needle)
            if matched is not None:
                filtered.append(matched)
        groups = filtered

    groups.sort(key=lambda g: (-g["count"], (g["display_name"] or "").casefold()))
    return groups


def _match_q(group: dict[str, Any], q: str) -> dict[str, Any] | None:
    needle = q.casefold()
    user_blob = " ".join(
        [
            str(group.get("display_name") or ""),
            str(group.get("phone_masked") or ""),
            str(group.get("user_id") or ""),
        ]
    ).casefold()
    user_hit = needle in user_blob
    if user_hit:
        return group
    memories = [item for item in group["memories"] if needle in item["content"].casefold()]
    if not memories:
        return None
    filtered = dict(group)
    filtered["memories"] = memories
    filtered["count"] = len(memories)
    return filtered


async def collect_mem0_memories(
    session: AsyncSession,
    *,
    user_id: UUID | None = None,
    q: str = "",
) -> dict[str, Any]:
    """拉取 Mem0 记忆并按用户分组。表不存在时 available=False。"""
    name = collection_name()
    schema = await find_collection_schema(session, name)
    empty = {
        "available": schema is not None,
        "collection": name,
        "schema": schema,
        "truncated": False,
        "total_memories": 0,
        "user_count": 0,
        "groups": [],
        "user": None,
        "q": q,
    }
    if schema is None:
        return empty

    qualified = f"{quote_ident(schema)}.{quote_ident(name)}"
    params: dict[str, Any] = {"cap": ROW_CAP}
    user_clause = ""
    if user_id is not None:
        user_clause = "AND payload->>'user_id' = :user_id"
        params["user_id"] = str(user_id)

    result = await session.execute(
        text(
            f"""
            SELECT id::text AS id, payload
            FROM {qualified}
            WHERE COALESCE(payload->>'data', payload->>'memory', payload->>'text', '') <> ''
              AND COALESCE(payload->>'type', '') <> 'user_identity'
              {user_clause}
            ORDER BY COALESCE(payload->>'updated_at', payload->>'created_at') DESC NULLS LAST
            LIMIT :cap
            """
        ),
        params,
    )
    rows = result.all()
    truncated = len(rows) >= ROW_CAP

    items: list[dict[str, Any]] = []
    for row in rows:
        parsed = parse_payload(str(row[0]), row[1])
        if parsed is not None:
            items.append(parsed)

    user_ids: list[UUID] = []
    seen_ids: set[UUID] = set()
    for item in items:
        raw = item.get("user_id")
        if not raw:
            continue
        try:
            uid = UUID(raw)
        except ValueError:
            continue
        if uid not in seen_ids:
            seen_ids.add(uid)
            user_ids.append(uid)

    users: dict[str, User] = {}
    if user_ids:
        loaded = (await session.scalars(select(User).where(User.id.in_(user_ids)))).all()
        users = {str(u.id): u for u in loaded}

    selected_user: User | None = None
    if user_id is not None:
        selected_user = users.get(str(user_id))
        if selected_user is None:
            selected_user = await session.get(User, user_id)

    groups = group_memory_items(items, users, q=q)

    return {
        "available": True,
        "collection": name,
        "schema": schema,
        "truncated": truncated,
        "total_memories": sum(g["count"] for g in groups),
        "user_count": len(groups),
        "groups": groups,
        "user": selected_user,
        "q": q,
    }


async def search_users(session: AsyncSession, q: str) -> list[User]:
    stmt = (
        select(User)
        .where(
            or_(
                User.display_name.ilike(f"%{q}%"),
                User.phone_masked.contains(q),
            )
        )
        .order_by(User.created_at.desc())
        .limit(20)
    )
    return list((await session.scalars(stmt)).all())
