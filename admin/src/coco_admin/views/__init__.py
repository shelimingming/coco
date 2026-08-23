"""注册 SQLAdmin 视图。"""

from __future__ import annotations

from pathlib import Path

from sqladmin import Admin
from sqlalchemy.ext.asyncio import AsyncEngine

from coco_admin.auth import AdminAuth
from coco_admin.config import AdminSettings
from coco_admin.views.llm_debug import LlmDebugView
from coco_admin.views.models import ALL_MODEL_VIEWS
from coco_admin.views.stats_view import StatsAdminView

TEMPLATES_DIR = str(Path(__file__).resolve().parent.parent / "templates")


def mount_admin(app, engine: AsyncEngine, settings: AdminSettings) -> Admin:
    """挂载 SQLAdmin 到独立 FastAPI app。"""
    authentication_backend = AdminAuth(settings)
    admin = Admin(
        app=app,
        engine=engine,
        title="Coco Admin",
        base_url="/admin",
        templates_dir=TEMPLATES_DIR,
        authentication_backend=authentication_backend,
    )
    admin.add_view(StatsAdminView)
    admin.add_view(LlmDebugView)
    for view in ALL_MODEL_VIEWS:
        admin.add_view(view)
    return admin
