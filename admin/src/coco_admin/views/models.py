"""11 张业务表的 SQLAdmin ModelView：默认只读，少量运营动作。"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from coco.models.auth import AuthSession, PhoneCode
from coco.models.care import CareShare, FamilyMessage
from coco.models.family import Family, FamilyInvite
from coco.models.memory import Memory
from coco.models.notification import Notification
from coco.models.reminder import Reminder, ReminderOccurrence
from coco.models.user import User, UserStatus
from sqladmin import ModelView, action
from sqladmin.filters import StaticValuesFilter
from starlette.requests import Request
from starlette.responses import RedirectResponse

from coco_admin.database import get_session_factory
from coco_admin.views.aggregates import load_family_aggregate, load_user_aggregate

try:
    # 新版 sqladmin 提供 Flash；旧版则降级为无 toast
    from sqladmin import Flash
except ImportError:  # pragma: no cover
    Flash = None  # type: ignore[misc, assignment]


def _flash_success(request: Request, message: str) -> None:
    if Flash is not None:
        Flash.success(request, message)


def _redirect_back(request: Request, identity: str) -> RedirectResponse:
    referer = request.headers.get("Referer")
    if referer:
        return RedirectResponse(referer, status_code=302)
    return RedirectResponse(request.url_for("admin:list", identity=identity), status_code=302)


class ReadOnlyModelView(ModelView):
    """业务数据默认不可新建/编辑/删除，避免运营误改。"""

    can_create = False
    can_edit = False
    can_delete = False
    can_view_details = True
    page_size = 50
    page_size_options = [25, 50, 100, 200]


class UserAdmin(ReadOnlyModelView, model=User):
    name = "用户"
    name_plural = "用户"
    icon = "fa-solid fa-user"
    category = "核心"
    column_list = [
        User.id,
        User.display_name,
        User.phone_masked,
        User.role,
        User.status,
        User.created_at,
    ]
    column_details_exclude_list = [User.phone_hash]
    column_searchable_list = [User.display_name, User.phone_masked]
    column_sortable_list = [User.created_at, User.role, User.status]
    column_filters = [
        StaticValuesFilter(User.role, values=[("parent", "父母"), ("child", "子女")]),
        StaticValuesFilter(User.status, values=[("active", "正常"), ("disabled", "已禁用")]),
    ]
    column_default_sort = [(User.created_at, True)]
    details_template = "sqladmin/user_details.html"

    async def details_context(self, request: Request) -> dict:
        pk = request.path_params.get("pk")
        if not pk:
            return {}
        factory = get_session_factory()
        async with factory() as session:
            data = await load_user_aggregate(session, UUID(str(pk)))
        return {"aggregate": data}

    @action(
        name="disable_users",
        label="禁用账号",
        confirmation_message="确认禁用所选用户？禁用后无法登录。",
        add_in_detail=True,
        add_in_list=True,
    )
    async def disable_users(self, request: Request) -> RedirectResponse:
        await self._set_status(request, UserStatus.DISABLED.value)
        _flash_success(request, "已禁用所选用户")
        return _redirect_back(request, self.identity)

    @action(
        name="enable_users",
        label="启用账号",
        confirmation_message="确认启用所选用户？",
        add_in_detail=True,
        add_in_list=True,
    )
    async def enable_users(self, request: Request) -> RedirectResponse:
        await self._set_status(request, UserStatus.ACTIVE.value)
        _flash_success(request, "已启用所选用户")
        return _redirect_back(request, self.identity)

    async def _set_status(self, request: Request, status: str) -> None:
        pks = [p for p in request.query_params.get("pks", "").split(",") if p]
        if not pks:
            return
        factory = get_session_factory()
        async with factory() as session:
            for pk in pks:
                user = await session.get(User, UUID(pk))
                if user is not None:
                    user.status = status
            await session.commit()


class FamilyAdmin(ReadOnlyModelView, model=Family):
    name = "家庭"
    name_plural = "家庭"
    icon = "fa-solid fa-house"
    category = "核心"
    column_list = [
        Family.id,
        Family.parent_user_id,
        Family.child_user_id,
        Family.status,
        Family.created_at,
    ]
    column_filters = [
        StaticValuesFilter(Family.status, values=[("active", "已绑定"), ("pending", "待加入")]),
    ]
    column_sortable_list = [Family.created_at, Family.status]
    column_default_sort = [(Family.created_at, True)]
    details_template = "sqladmin/family_details.html"

    async def details_context(self, request: Request) -> dict:
        pk = request.path_params.get("pk")
        if not pk:
            return {}
        factory = get_session_factory()
        async with factory() as session:
            data = await load_family_aggregate(session, UUID(str(pk)))
        return {"aggregate": data}


class FamilyInviteAdmin(ReadOnlyModelView, model=FamilyInvite):
    name = "家庭邀请码"
    name_plural = "家庭邀请码"
    icon = "fa-solid fa-ticket"
    category = "核心"
    column_list = [
        FamilyInvite.id,
        FamilyInvite.code,
        FamilyInvite.family_id,
        FamilyInvite.inviter_user_id,
        FamilyInvite.expires_at,
        FamilyInvite.consumed_at,
        FamilyInvite.created_at,
    ]
    column_searchable_list = [FamilyInvite.code]
    column_sortable_list = [FamilyInvite.created_at, FamilyInvite.expires_at]
    column_default_sort = [(FamilyInvite.created_at, True)]


class ReminderAdmin(ReadOnlyModelView, model=Reminder):
    name = "提醒"
    name_plural = "提醒"
    icon = "fa-solid fa-bell"
    category = "业务"
    column_list = [
        Reminder.id,
        Reminder.user_id,
        Reminder.title,
        Reminder.schedule_type,
        Reminder.schedule_time,
        Reminder.status,
        Reminder.created_source,
        Reminder.next_trigger_at,
        Reminder.created_at,
    ]
    column_searchable_list = [Reminder.title]
    column_filters = [
        StaticValuesFilter(
            Reminder.status,
            values=[
                ("ACTIVE", "进行中"),
                ("PAUSED", "已暂停"),
                ("DONE", "已完成"),
                ("DELETED", "已删除"),
            ],
        ),
        StaticValuesFilter(Reminder.schedule_type, values=[("ONCE", "一次性"), ("DAILY", "每日")]),
    ]
    column_sortable_list = [Reminder.created_at, Reminder.next_trigger_at, Reminder.status]
    column_default_sort = [(Reminder.created_at, True)]


class ReminderOccurrenceAdmin(ReadOnlyModelView, model=ReminderOccurrence):
    name = "提醒发生记录"
    name_plural = "提醒发生记录"
    icon = "fa-solid fa-clock-rotate-left"
    category = "业务"
    column_list = [
        ReminderOccurrence.id,
        ReminderOccurrence.reminder_id,
        ReminderOccurrence.due_at,
        ReminderOccurrence.state,
        ReminderOccurrence.first_notified_at,
        ReminderOccurrence.second_notified_at,
        ReminderOccurrence.confirmed_at,
        ReminderOccurrence.escalated_at,
    ]
    column_filters = [
        StaticValuesFilter(
            ReminderOccurrence.state,
            values=[
                ("WAITING", "等待"),
                ("FIRST_REMINDER", "首次提醒"),
                ("SECOND_REMINDER", "二次提醒"),
                ("DONE", "已确认"),
                ("ESCALATED", "已升级"),
            ],
        ),
    ]
    column_sortable_list = [ReminderOccurrence.due_at, ReminderOccurrence.state]
    column_default_sort = [(ReminderOccurrence.due_at, True)]


class MemoryAdmin(ReadOnlyModelView, model=Memory):
    name = "记忆"
    name_plural = "记忆"
    icon = "fa-solid fa-brain"
    category = "业务"
    column_list = [
        Memory.id,
        Memory.user_id,
        Memory.category,
        Memory.source,
        Memory.confirmed,
        Memory.content,
        Memory.created_at,
    ]
    column_searchable_list = [Memory.content]
    column_filters = [
        StaticValuesFilter(
            Memory.category,
            values=[
                ("PROFILE", "个人"),
                ("FAMILY", "家庭"),
                ("PREFERENCE", "偏好"),
                ("ROUTINE", "作息"),
            ],
        ),
    ]
    column_sortable_list = [Memory.created_at, Memory.category]
    column_default_sort = [(Memory.created_at, True)]


class CareShareAdmin(ReadOnlyModelView, model=CareShare):
    name = "关怀摘要"
    name_plural = "关怀摘要"
    icon = "fa-solid fa-heart"
    category = "业务"
    column_list = [
        CareShare.id,
        CareShare.parent_id,
        CareShare.child_id,
        CareShare.urgency,
        CareShare.reply_expectation,
        CareShare.parent_confirmed,
        CareShare.read_at,
        CareShare.summary,
        CareShare.created_at,
    ]
    column_searchable_list = [CareShare.summary]
    column_filters = [
        StaticValuesFilter(CareShare.urgency, values=[("LOW", "低"), ("ATTENTION", "需关注")]),
    ]
    column_sortable_list = [CareShare.created_at, CareShare.urgency]
    column_default_sort = [(CareShare.created_at, True)]


class FamilyMessageAdmin(ReadOnlyModelView, model=FamilyMessage):
    name = "家庭消息"
    name_plural = "家庭消息"
    icon = "fa-solid fa-comments"
    category = "业务"
    column_list = [
        FamilyMessage.id,
        FamilyMessage.family_id,
        FamilyMessage.kind,
        FamilyMessage.from_user_id,
        FamilyMessage.to_user_id,
        FamilyMessage.original_text,
        FamilyMessage.delivered_text,
        FamilyMessage.acknowledged_at,
        FamilyMessage.created_at,
    ]
    column_searchable_list = [FamilyMessage.original_text, FamilyMessage.delivered_text]
    column_filters = [
        StaticValuesFilter(
            FamilyMessage.kind,
            values=[("CHILD_STATUS", "子女报平安"), ("PARENT_REPLY", "父母回复")],
        ),
    ]
    column_sortable_list = [FamilyMessage.created_at, FamilyMessage.kind]
    column_default_sort = [(FamilyMessage.created_at, True)]


class NotificationAdmin(ReadOnlyModelView, model=Notification):
    name = "通知"
    name_plural = "通知"
    icon = "fa-solid fa-envelope"
    category = "业务"
    column_list = [
        Notification.id,
        Notification.user_id,
        Notification.type,
        Notification.title,
        Notification.body,
        Notification.read_at,
        Notification.created_at,
    ]
    column_searchable_list = [Notification.title, Notification.body]
    column_filters = [
        StaticValuesFilter(
            Notification.type,
            values=[
                ("REMINDER", "提醒"),
                ("CARE_MESSAGE", "关怀"),
                ("CHILD_STATUS", "子女状态"),
            ],
        ),
    ]
    column_sortable_list = [Notification.created_at, Notification.type]
    column_default_sort = [(Notification.created_at, True)]


class AuthSessionAdmin(ReadOnlyModelView, model=AuthSession):
    name = "登录会话"
    name_plural = "登录会话"
    icon = "fa-solid fa-key"
    category = "鉴权运维"
    column_list = [
        AuthSession.id,
        AuthSession.user_id,
        AuthSession.device_id,
        AuthSession.expires_at,
        AuthSession.revoked_at,
        AuthSession.created_at,
    ]
    # refresh hash 不展示
    column_details_exclude_list = [AuthSession.refresh_token_hash]
    column_sortable_list = [AuthSession.created_at, AuthSession.expires_at]
    column_default_sort = [(AuthSession.created_at, True)]

    @action(
        name="revoke_sessions",
        label="吊销会话",
        confirmation_message="确认吊销所选会话？用户需重新登录。",
        add_in_detail=True,
        add_in_list=True,
    )
    async def revoke_sessions(self, request: Request) -> RedirectResponse:
        pks = [p for p in request.query_params.get("pks", "").split(",") if p]
        if pks:
            now = datetime.now(UTC)
            factory = get_session_factory()
            async with factory() as session:
                for pk in pks:
                    row = await session.get(AuthSession, UUID(pk))
                    if row is not None and row.revoked_at is None:
                        row.revoked_at = now
                await session.commit()
            _flash_success(request, "已吊销所选会话")
        return _redirect_back(request, self.identity)


class PhoneCodeAdmin(ReadOnlyModelView, model=PhoneCode):
    name = "验证码记录"
    name_plural = "验证码记录"
    icon = "fa-solid fa-shield-halved"
    category = "鉴权运维"
    # 仅 hash，无法还原明文手机号与验证码
    column_list = [
        PhoneCode.id,
        PhoneCode.purpose,
        PhoneCode.attempts,
        PhoneCode.expires_at,
        PhoneCode.consumed_at,
        PhoneCode.created_at,
    ]
    column_details_exclude_list = [PhoneCode.phone_hash, PhoneCode.code_hash]
    column_sortable_list = [PhoneCode.created_at, PhoneCode.expires_at]
    column_default_sort = [(PhoneCode.created_at, True)]


ALL_MODEL_VIEWS: list[type[ModelView]] = [
    UserAdmin,
    FamilyAdmin,
    FamilyInviteAdmin,
    ReminderAdmin,
    ReminderOccurrenceAdmin,
    MemoryAdmin,
    CareShareAdmin,
    FamilyMessageAdmin,
    NotificationAdmin,
    AuthSessionAdmin,
    PhoneCodeAdmin,
]
