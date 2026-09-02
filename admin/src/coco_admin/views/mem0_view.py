"""Mem0 隐式记忆：按用户只读浏览。"""

from __future__ import annotations

from uuid import UUID

from sqladmin import BaseView, expose
from starlette.requests import Request
from starlette.responses import Response

from coco_admin.database import get_session_factory
from coco_admin.mem0_memories.service import (
    collect_mem0_memories,
    collection_name,
    search_users,
)


class Mem0MemoriesView(BaseView):
    name = "Mem0 记忆"
    icon = "fa-solid fa-brain"
    category = "调试"

    @expose("/mem0", methods=["GET"])
    async def index(self, request: Request) -> Response:
        q = (request.query_params.get("q") or "").strip()
        factory = get_session_factory()
        async with factory() as session:
            data = await collect_mem0_memories(session, q=q)
            # 有搜索词但没扫到记忆时，仍列出匹配用户，方便点进个人页
            users = await search_users(session, q) if q and not data["groups"] else []
        return await self.templates.TemplateResponse(
            request,
            "sqladmin/mem0_memories.html",
            {**data, "users": users},
        )

    @expose("/mem0/user/{user_id}", methods=["GET"])
    async def user_memories(self, request: Request) -> Response:
        q = (request.query_params.get("q") or "").strip()
        raw_id = request.path_params.get("user_id")
        try:
            user_id = UUID(str(raw_id))
        except ValueError:
            return await self.templates.TemplateResponse(
                request,
                "sqladmin/mem0_memories.html",
                {
                    "available": True,
                    "collection": collection_name(),
                    "schema": None,
                    "truncated": False,
                    "total_memories": 0,
                    "user_count": 0,
                    "groups": [],
                    "user": None,
                    "q": q,
                    "users": [],
                },
            )
        factory = get_session_factory()
        async with factory() as session:
            data = await collect_mem0_memories(session, user_id=user_id, q=q)
        return await self.templates.TemplateResponse(
            request,
            "sqladmin/mem0_memories.html",
            {**data, "users": []},
        )
