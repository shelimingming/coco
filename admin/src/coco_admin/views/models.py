"""业务表的 SQLAdmin ModelView：默认只读，少量运营动作。

列表不展示 UUID 主键；用户/家庭/提醒/会话外键展示可读名称，完整 id 仅在详情可见。
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, ClassVar
from uuid import UUID

from coco.models.auth import AuthSession, PhoneCode
from coco.models.care import CareShare, FamilyMessage
from coco.models.conversation import Conversation, ConversationItem
from coco.models.family import Family, FamilyInvite
from coco.models.llm_trace import LlmTrace
from coco.models.notification import Notification
from coco.models.reminder import Reminder, ReminderOccurrence
from coco.models.user import User, UserStatus
from sqladmin import ModelView, action
from sqladmin.filters import StaticValuesFilter
from sqladmin.pagination import Pagination
from starlette.requests import Request
from starlette.responses import RedirectResponse

from coco_admin.database import get_session_factory
from coco_admin.views.aggregates import (
    load_conversation_aggregate,
    load_family_aggregate,
    load_user_aggregate,
)
from coco_admin.views.labels import (
    format_conversation_label,
    format_conversation_label_detail,
    format_family_label,
    format_family_label_detail,
    format_reminder_title,
    format_reminder_title_detail,
    format_user_name,
    format_user_name_detail,
    warm_admin_labels,
)
from coco_admin.views.llm_debug import PURPOSE_LABELS

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

    # 列表页需预加载的外键属性名（用于可读标签）
    label_user_attrs: ClassVar[tuple[str, ...]] = ()
    label_family_attrs: ClassVar[tuple[str, ...]] = ()
    label_reminder_attrs: ClassVar[tuple[str, ...]] = ()
    label_conversation_attrs: ClassVar[tuple[str, ...]] = ()

    async def list(self, request: Request) -> Pagination:
        pagination = await super().list(request)
        await warm_admin_labels(
            request,
            pagination.rows,
            user_attrs=self.label_user_attrs,
            family_attrs=self.label_family_attrs,
            reminder_attrs=self.label_reminder_attrs,
            conversation_attrs=self.label_conversation_attrs,
        )
        return pagination

    async def get_object_for_details(self, request: Request) -> Any:
        model = await super().get_object_for_details(request)
        if model is not None:
            await warm_admin_labels(
                request,
                [model],
                user_attrs=self.label_user_attrs,
                family_attrs=self.label_family_attrs,
                reminder_attrs=self.label_reminder_attrs,
                conversation_attrs=self.label_conversation_attrs,
            )
        return model


class UserAdmin(ReadOnlyModelView, model=User):
    name = "用户"
    name_plural = "用户"
    icon = "fa-solid fa-user"
    category = "核心"
    column_list = [
        User.display_name,
        User.phone_masked,
        User.role,
        User.status,
        User.created_at,
    ]
    column_labels = {
        User.display_name: "用户名",
        User.phone_masked: "手机号",
        User.phone_e164: "手机号明文",
        User.role: "角色",
        User.status: "状态",
        User.created_at: "创建时间",
        User.id: "用户 ID",
    }
    column_details_exclude_list = [User.phone_hash]
    # 列表仍用掩码；详情可见 phone_e164 便于排障
    column_searchable_list = [User.display_name, User.phone_masked, User.phone_e164]
    column_sortable_list = [User.created_at, User.role, User.status, User.display_name]
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
    label_user_attrs = ("parent_user_id", "child_user_id")
    column_list = [
        Family.parent_user_id,
        Family.child_user_id,
        Family.status,
        Family.created_at,
    ]
    column_labels = {
        Family.parent_user_id: "父母",
        Family.child_user_id: "子女",
        Family.status: "状态",
        Family.created_at: "创建时间",
        Family.id: "家庭 ID",
    }
    column_formatters = {
        Family.parent_user_id: format_user_name,
        Family.child_user_id: format_user_name,
    }
    column_formatters_detail = {
        Family.parent_user_id: format_user_name_detail,
        Family.child_user_id: format_user_name_detail,
    }
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
    name = "家庭邀请链接"
    name_plural = "家庭邀请链接"
    icon = "fa-solid fa-ticket"
    category = "核心"
    label_user_attrs = ("inviter_user_id",)
    label_family_attrs = ("family_id",)
    column_list = [
        FamilyInvite.token,
        FamilyInvite.family_id,
        FamilyInvite.inviter_user_id,
        FamilyInvite.consumed_at,
        FamilyInvite.created_at,
    ]
    column_labels = {
        FamilyInvite.token: "链接 token",
        FamilyInvite.family_id: "家庭",
        FamilyInvite.inviter_user_id: "邀请人",
        FamilyInvite.consumed_at: "使用时间",
        FamilyInvite.created_at: "创建时间",
        FamilyInvite.id: "记录 ID",
    }
    column_formatters = {
        FamilyInvite.family_id: format_family_label,
        FamilyInvite.inviter_user_id: format_user_name,
    }
    column_formatters_detail = {
        FamilyInvite.family_id: format_family_label_detail,
        FamilyInvite.inviter_user_id: format_user_name_detail,
    }
    column_searchable_list = [FamilyInvite.token]
    column_sortable_list = [FamilyInvite.created_at, FamilyInvite.consumed_at]
    column_default_sort = [(FamilyInvite.created_at, True)]


class ReminderAdmin(ReadOnlyModelView, model=Reminder):
    name = "提醒"
    name_plural = "提醒"
    icon = "fa-solid fa-bell"
    category = "业务"
    label_user_attrs = ("user_id",)
    column_list = [
        Reminder.title,
        Reminder.user_id,
        Reminder.schedule_type,
        Reminder.schedule_time,
        Reminder.status,
        Reminder.created_source,
        Reminder.next_trigger_at,
        Reminder.created_at,
    ]
    column_labels = {
        Reminder.title: "标题",
        Reminder.user_id: "用户",
        Reminder.schedule_type: "类型",
        Reminder.schedule_time: "时间",
        Reminder.status: "状态",
        Reminder.created_source: "来源",
        Reminder.next_trigger_at: "下次触发",
        Reminder.created_at: "创建时间",
        Reminder.id: "提醒 ID",
    }
    column_formatters = {Reminder.user_id: format_user_name}
    column_formatters_detail = {Reminder.user_id: format_user_name_detail}
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
    label_reminder_attrs = ("reminder_id",)
    column_list = [
        ReminderOccurrence.reminder_id,
        ReminderOccurrence.due_at,
        ReminderOccurrence.delivery_state,
        ReminderOccurrence.response_status,
        ReminderOccurrence.first_notified_at,
        ReminderOccurrence.second_notified_at,
        ReminderOccurrence.confirmed_at,
        ReminderOccurrence.escalated_at,
    ]
    column_labels = {
        ReminderOccurrence.reminder_id: "提醒",
        ReminderOccurrence.due_at: "到期时间",
        ReminderOccurrence.delivery_state: "投递进展",
        ReminderOccurrence.response_status: "用户反馈",
        ReminderOccurrence.first_notified_at: "首次通知",
        ReminderOccurrence.second_notified_at: "二次通知",
        ReminderOccurrence.confirmed_at: "确认时间",
        ReminderOccurrence.escalated_at: "升级时间",
        ReminderOccurrence.id: "记录 ID",
    }
    column_formatters = {ReminderOccurrence.reminder_id: format_reminder_title}
    column_formatters_detail = {ReminderOccurrence.reminder_id: format_reminder_title_detail}
    column_filters = [
        StaticValuesFilter(
            ReminderOccurrence.delivery_state,
            values=[
                ("PENDING", "待提示"),
                ("NOTIFIED_1", "已提示一次"),
                ("NOTIFIED_2", "已提示两次"),
                ("CLOSED", "已关闭"),
            ],
        ),
        StaticValuesFilter(
            ReminderOccurrence.response_status,
            values=[
                ("NONE", "无"),
                ("COMPLETED_SELF_REPORTED", "自述完成"),
                ("SKIPPED_SELF_REPORTED", "本次跳过"),
                ("SNOOZED", "已延后"),
                ("UNANSWERED", "无回应"),
            ],
        ),
    ]
    column_sortable_list = [
        ReminderOccurrence.due_at,
        ReminderOccurrence.delivery_state,
    ]
    column_default_sort = [(ReminderOccurrence.due_at, True)]


class ConversationAdmin(ReadOnlyModelView, model=Conversation):
    name = "语音会话"
    name_plural = "语音会话"
    icon = "fa-solid fa-headset"
    category = "业务"
    label_user_attrs = ("user_id",)
    column_list = [
        Conversation.user_id,
        Conversation.title,
        Conversation.status,
        Conversation.channel,
        Conversation.started_at,
        Conversation.ended_at,
        Conversation.created_at,
    ]
    column_labels = {
        Conversation.user_id: "用户",
        Conversation.title: "标题",
        Conversation.status: "状态",
        Conversation.channel: "通道",
        Conversation.started_at: "开始时间",
        Conversation.ended_at: "结束时间",
        Conversation.created_at: "创建时间",
        Conversation.id: "会话 ID",
    }
    column_formatters = {Conversation.user_id: format_user_name}
    column_formatters_detail = {Conversation.user_id: format_user_name_detail}
    column_filters = [
        StaticValuesFilter(
            Conversation.status,
            values=[
                ("ACTIVE", "进行中"),
                ("CLOSED", "已结束"),
                ("ERROR", "异常结束"),
            ],
        ),
        StaticValuesFilter(
            Conversation.channel,
            values=[("VOICE_REALTIME", "实时语音"), ("LOOK", "帮我看看")],
        ),
    ]
    column_sortable_list = [
        Conversation.started_at,
        Conversation.ended_at,
        Conversation.status,
        Conversation.created_at,
    ]
    column_default_sort = [(Conversation.started_at, True)]
    details_template = "sqladmin/conversation_details.html"

    async def details_context(self, request: Request) -> dict:
        pk = request.path_params.get("pk")
        if not pk:
            return {}
        factory = get_session_factory()
        async with factory() as session:
            data = await load_conversation_aggregate(session, UUID(str(pk)))
        return {"aggregate": data}


class ConversationItemAdmin(ReadOnlyModelView, model=ConversationItem):
    name = "会话条目"
    name_plural = "会话条目"
    icon = "fa-solid fa-list-ul"
    category = "业务"
    label_conversation_attrs = ("conversation_id",)
    column_list = [
        ConversationItem.conversation_id,
        ConversationItem.seq,
        ConversationItem.kind,
        ConversationItem.text,
        ConversationItem.tool_name,
        ConversationItem.display_summary,
        ConversationItem.created_at,
    ]
    column_labels = {
        ConversationItem.conversation_id: "会话",
        ConversationItem.seq: "序号",
        ConversationItem.kind: "类型",
        ConversationItem.text: "文本",
        ConversationItem.tool_name: "工具",
        ConversationItem.display_summary: "白话摘要",
        ConversationItem.arguments_json: "工具参数",
        ConversationItem.result_json: "工具结果",
        ConversationItem.created_at: "创建时间",
        ConversationItem.id: "条目 ID",
    }
    column_formatters = {ConversationItem.conversation_id: format_conversation_label}
    column_formatters_detail = {
        ConversationItem.conversation_id: format_conversation_label_detail,
    }
    column_searchable_list = [
        ConversationItem.text,
        ConversationItem.display_summary,
        ConversationItem.tool_name,
    ]
    column_filters = [
        StaticValuesFilter(
            ConversationItem.kind,
            values=[
                ("USER", "用户"),
                ("ASSISTANT", "可可"),
                ("TOOL", "工具"),
            ],
        ),
    ]
    column_sortable_list = [
        ConversationItem.created_at,
        ConversationItem.seq,
        ConversationItem.kind,
    ]
    column_default_sort = [(ConversationItem.created_at, True)]


class CareShareAdmin(ReadOnlyModelView, model=CareShare):
    name = "关怀摘要"
    name_plural = "关怀摘要"
    icon = "fa-solid fa-heart"
    category = "业务"
    label_user_attrs = ("parent_id", "child_id")
    column_list = [
        CareShare.parent_id,
        CareShare.child_id,
        CareShare.urgency,
        CareShare.reply_expectation,
        CareShare.parent_confirmed,
        CareShare.read_at,
        CareShare.summary,
        CareShare.created_at,
    ]
    column_labels = {
        CareShare.parent_id: "父母",
        CareShare.child_id: "子女",
        CareShare.urgency: "紧急度",
        CareShare.reply_expectation: "回复预期",
        CareShare.parent_confirmed: "父母已确认",
        CareShare.read_at: "已读时间",
        CareShare.summary: "摘要",
        CareShare.created_at: "创建时间",
        CareShare.id: "记录 ID",
    }
    column_formatters = {
        CareShare.parent_id: format_user_name,
        CareShare.child_id: format_user_name,
    }
    column_formatters_detail = {
        CareShare.parent_id: format_user_name_detail,
        CareShare.child_id: format_user_name_detail,
    }
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
    label_user_attrs = ("from_user_id", "to_user_id")
    label_family_attrs = ("family_id",)
    column_list = [
        FamilyMessage.kind,
        FamilyMessage.family_id,
        FamilyMessage.from_user_id,
        FamilyMessage.to_user_id,
        FamilyMessage.original_text,
        FamilyMessage.delivered_text,
        FamilyMessage.acknowledged_at,
        FamilyMessage.created_at,
    ]
    column_labels = {
        FamilyMessage.kind: "类型",
        FamilyMessage.family_id: "家庭",
        FamilyMessage.from_user_id: "发送方",
        FamilyMessage.to_user_id: "接收方",
        FamilyMessage.original_text: "原文",
        FamilyMessage.delivered_text: "送达文案",
        FamilyMessage.acknowledged_at: "确认时间",
        FamilyMessage.created_at: "创建时间",
        FamilyMessage.id: "消息 ID",
    }
    column_formatters = {
        FamilyMessage.family_id: format_family_label,
        FamilyMessage.from_user_id: format_user_name,
        FamilyMessage.to_user_id: format_user_name,
    }
    column_formatters_detail = {
        FamilyMessage.family_id: format_family_label_detail,
        FamilyMessage.from_user_id: format_user_name_detail,
        FamilyMessage.to_user_id: format_user_name_detail,
    }
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
    label_user_attrs = ("user_id",)
    column_list = [
        Notification.user_id,
        Notification.type,
        Notification.title,
        Notification.body,
        Notification.read_at,
        Notification.created_at,
    ]
    column_labels = {
        Notification.user_id: "用户",
        Notification.type: "类型",
        Notification.title: "标题",
        Notification.body: "正文",
        Notification.read_at: "已读时间",
        Notification.created_at: "创建时间",
        Notification.id: "通知 ID",
    }
    column_formatters = {Notification.user_id: format_user_name}
    column_formatters_detail = {Notification.user_id: format_user_name_detail}
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
    label_user_attrs = ("user_id",)
    column_list = [
        AuthSession.user_id,
        AuthSession.device_id,
        AuthSession.expires_at,
        AuthSession.revoked_at,
        AuthSession.created_at,
    ]
    column_labels = {
        AuthSession.user_id: "用户",
        AuthSession.device_id: "设备",
        AuthSession.expires_at: "过期时间",
        AuthSession.revoked_at: "吊销时间",
        AuthSession.created_at: "创建时间",
        AuthSession.id: "会话 ID",
    }
    column_formatters = {AuthSession.user_id: format_user_name}
    column_formatters_detail = {AuthSession.user_id: format_user_name_detail}
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
    # 仅 hash，无法还原明文手机号与验证码；列表也不展示 UUID
    column_list = [
        PhoneCode.purpose,
        PhoneCode.attempts,
        PhoneCode.expires_at,
        PhoneCode.consumed_at,
        PhoneCode.created_at,
    ]
    column_labels = {
        PhoneCode.purpose: "用途",
        PhoneCode.attempts: "尝试次数",
        PhoneCode.expires_at: "过期时间",
        PhoneCode.consumed_at: "使用时间",
        PhoneCode.created_at: "创建时间",
        PhoneCode.id: "记录 ID",
    }
    column_details_exclude_list = [PhoneCode.phone_hash, PhoneCode.code_hash]
    column_sortable_list = [PhoneCode.created_at, PhoneCode.expires_at]
    column_default_sort = [(PhoneCode.created_at, True)]


class LlmTraceAdmin(ReadOnlyModelView, model=LlmTrace):
    name = "模型调用"
    name_plural = "模型调用"
    icon = "fa-solid fa-microchip"
    category = "调试"
    label_user_attrs = ("user_id",)
    label_conversation_attrs = ("conversation_id",)
    column_list = [
        LlmTrace.started_at,
        LlmTrace.user_id,
        LlmTrace.purpose,
        LlmTrace.model,
        LlmTrace.status,
        LlmTrace.latency_ms,
        LlmTrace.modality,
    ]
    column_labels = {
        LlmTrace.started_at: "开始时间",
        LlmTrace.user_id: "用户",
        LlmTrace.conversation_id: "会话",
        LlmTrace.purpose: "用途",
        LlmTrace.modality: "模态",
        LlmTrace.provider: "供应商",
        LlmTrace.model: "模型",
        LlmTrace.status: "状态",
        LlmTrace.latency_ms: "耗时(ms)",
        LlmTrace.request_json: "请求",
        LlmTrace.response_json: "响应",
        LlmTrace.usage_json: "用量",
        LlmTrace.error_message: "错误",
        LlmTrace.id: "记录 ID",
    }
    column_formatters = {
        LlmTrace.user_id: format_user_name,
        LlmTrace.conversation_id: format_conversation_label,
        LlmTrace.purpose: lambda m, a, request=None: PURPOSE_LABELS.get(
            getattr(m, a, ""), getattr(m, a, "")
        ),
    }
    column_formatters_detail = {
        LlmTrace.user_id: format_user_name_detail,
        LlmTrace.conversation_id: format_conversation_label_detail,
        LlmTrace.purpose: lambda m, a, request=None: PURPOSE_LABELS.get(
            getattr(m, a, ""), getattr(m, a, "")
        ),
    }
    column_filters = [
        StaticValuesFilter(
            LlmTrace.purpose,
            values=list(PURPOSE_LABELS.items()),
        ),
        StaticValuesFilter(
            LlmTrace.status,
            values=[("ok", "成功"), ("error", "失败"), ("skipped", "跳过")],
        ),
    ]
    column_sortable_list = [
        LlmTrace.started_at,
        LlmTrace.purpose,
        LlmTrace.status,
        LlmTrace.latency_ms,
    ]
    column_default_sort = [(LlmTrace.started_at, True)]
    column_searchable_list = [LlmTrace.purpose, LlmTrace.model, LlmTrace.error_message]


ALL_MODEL_VIEWS: list[type[ModelView]] = [
    UserAdmin,
    FamilyAdmin,
    FamilyInviteAdmin,
    ReminderAdmin,
    ReminderOccurrenceAdmin,
    ConversationAdmin,
    ConversationItemAdmin,
    CareShareAdmin,
    FamilyMessageAdmin,
    NotificationAdmin,
    AuthSessionAdmin,
    PhoneCodeAdmin,
    LlmTraceAdmin,
]
