"""每日小记：按日生成图文、设置门禁、条件分享给子女。"""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.conversation import Conversation, ConversationItem, ConversationItemKind
from coco.models.daily_note import (
    DailyNote,
    DailyNoteImage,
    DailyNoteSettings,
    DailyNoteSource,
    DailyNoteStatus,
)
from coco.models.family import Family, FamilyStatus
from coco.models.notification import Notification, NotificationType
from coco.models.user import User, UserGender, UserRole
from coco.modules.daily_notes.schemas import (
    DailyNoteImageMeta,
    DailyNoteResponse,
    DailyNoteSettingsResponse,
    DailyNoteSettingsUpdateRequest,
)
from coco.observability.llm_trace import (
    PURPOSE_IMAGE_GENERATE,
    bind_llm_trace,
    record_llm_trace,
    reset_llm_trace,
)
from coco.providers.qwen_text import daily_note_items_or_fallback
from coco.providers.wan_image import WanImageClient

logger = logging.getLogger(__name__)

_COCO_LOOK = (
    "一只可爱的金毛寻回犬小狗可可，圆润卡通风格，温暖阳光，"
    "戴青色项圈，表情友善"
)
_PROMPT_MAX = 500
_IMAGE_MAX_BYTES = 4 * 1024 * 1024


def _elder_look(gender: str) -> str:
    if gender == UserGender.MALE.value:
        return "一位慈祥的中国老年男性，短发，温和微笑，日常家居服装"
    if gender == UserGender.FEMALE.value:
        return "一位慈祥的中国老年女性，花白短发，温和微笑，日常家居服装"
    return "一位慈祥的中国长辈，温和微笑，日常家居服装"


def _local_today(settings: Settings) -> date:
    return datetime.now(ZoneInfo(settings.local_timezone)).date()


def _day_bounds_utc(settings: Settings, note_date: date) -> tuple[datetime, datetime]:
    tz = ZoneInfo(settings.local_timezone)
    start_local = datetime(note_date.year, note_date.month, note_date.day, tzinfo=tz)
    end_local = start_local + timedelta(days=1)
    return start_local.astimezone(UTC), end_local.astimezone(UTC)


def _image_url_path(note_id: UUID, image_id: UUID) -> str:
    return f"/v1/daily-notes/{note_id}/images/{image_id}"


def _to_note_response(note: DailyNote, images: list[DailyNoteImage]) -> DailyNoteResponse:
    items = note.items_json if isinstance(note.items_json, list) else []
    str_items = [str(x) for x in items if isinstance(x, str) and x.strip()]
    return DailyNoteResponse(
        id=note.id,
        note_date=note.note_date,
        items=str_items,
        body_text=note.body_text or "\n".join(str_items),
        status=note.status,
        source=note.source,
        shared_at=note.shared_at,
        images=[
            DailyNoteImageMeta(
                id=img.id,
                seq=img.seq,
                mime_type=img.mime_type,
                url_path=_image_url_path(note.id, img.id),
            )
            for img in sorted(images, key=lambda i: i.seq)
        ],
        created_at=note.created_at,
    )


class DailyNoteService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def get_or_create_settings(
        self, session: AsyncSession, *, user: User
    ) -> DailyNoteSettings:
        row = await session.get(DailyNoteSettings, user.id)
        if row is None:
            row = DailyNoteSettings(
                user_id=user.id,
                generate_enabled=True,
                share_to_child_enabled=False,
                generate_hour=20,
            )
            session.add(row)
            await session.commit()
            await session.refresh(row)
        return row

    async def get_settings(
        self, session: AsyncSession, *, user: User
    ) -> DailyNoteSettingsResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以管理每日小记。")
        settings = await self.get_or_create_settings(session, user=user)
        gender = user.gender if user.gender in {g.value for g in UserGender} else UserGender.UNKNOWN.value
        return DailyNoteSettingsResponse(
            generate_enabled=settings.generate_enabled,
            share_to_child_enabled=settings.share_to_child_enabled,
            generate_hour=settings.generate_hour,
            gender=gender,  # type: ignore[arg-type]
        )

    async def update_settings(
        self,
        session: AsyncSession,
        *,
        user: User,
        body: DailyNoteSettingsUpdateRequest,
    ) -> DailyNoteSettingsResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以管理每日小记。")
        settings = await self.get_or_create_settings(session, user=user)
        if body.generate_enabled is not None:
            settings.generate_enabled = body.generate_enabled
        if body.share_to_child_enabled is not None:
            settings.share_to_child_enabled = body.share_to_child_enabled
        if body.gender is not None:
            user.gender = body.gender
        await session.commit()
        await session.refresh(user)
        return await self.get_settings(session, user=user)

    async def list_for_parent(
        self, session: AsyncSession, *, user: User, limit: int = 60
    ) -> list[DailyNoteResponse]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以查看每日小记。")
        result = await session.execute(
            select(DailyNote)
            .where(
                DailyNote.parent_id == user.id,
                DailyNote.status.in_(
                    [DailyNoteStatus.READY.value, DailyNoteStatus.EMPTY.value]
                ),
            )
            .order_by(DailyNote.note_date.desc())
            .limit(limit)
        )
        notes = list(result.scalars().all())
        return [await self._response_with_images(session, n) for n in notes]

    async def get_for_parent(
        self, session: AsyncSession, *, user: User, note_id: UUID
    ) -> DailyNoteResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以查看每日小记。")
        note = await session.get(DailyNote, note_id)
        if note is None or note.parent_id != user.id:
            raise AppError(404, "daily_note.not_found", "找不到这条每日小记。")
        return await self._response_with_images(session, note)

    async def child_today(
        self, session: AsyncSession, *, user: User
    ) -> DailyNoteResponse | None:
        """子女近况：仅返回已分享的今日小记。"""
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "daily_note.child_required", "只有子女模式可以查看家人小记。")
        family = await session.scalar(
            select(Family).where(
                Family.child_user_id == user.id,
                Family.status == FamilyStatus.ACTIVE.value,
                Family.parent_user_id.is_not(None),
            )
        )
        if family is None or family.parent_user_id is None:
            return None
        today = _local_today(self._settings)
        note = await session.scalar(
            select(DailyNote).where(
                DailyNote.parent_id == family.parent_user_id,
                DailyNote.note_date == today,
                DailyNote.status == DailyNoteStatus.READY.value,
                DailyNote.shared_at.is_not(None),
            )
        )
        if note is None:
            return None
        return await self._response_with_images(session, note)

    async def get_image_bytes(
        self,
        session: AsyncSession,
        *,
        user: User,
        note_id: UUID,
        image_id: UUID,
    ) -> tuple[bytes, str]:
        note = await session.get(DailyNote, note_id)
        if note is None:
            raise AppError(404, "daily_note.not_found", "找不到这条每日小记。")
        await self._assert_can_view_note(session, user=user, note=note)
        image = await session.get(DailyNoteImage, image_id)
        if image is None or image.daily_note_id != note.id:
            raise AppError(404, "daily_note.image_not_found", "找不到这张配图。")
        return image.data, image.mime_type

    async def generate_for_parent(
        self,
        session: AsyncSession,
        *,
        user: User,
        source: str = DailyNoteSource.MANUAL.value,
        note_date: date | None = None,
        respect_generate_enabled: bool = True,
    ) -> DailyNoteResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以生成每日小记。")
        settings = await self.get_or_create_settings(session, user=user)
        if respect_generate_enabled and not settings.generate_enabled:
            raise AppError(
                400,
                "daily_note.generate_disabled",
                "每日小记生成已关闭。您可以在设置里重新打开。",
            )

        target_date = note_date or _local_today(self._settings)
        note = await self._upsert_pending(
            session, parent_id=user.id, note_date=target_date, source=source
        )

        try:
            transcript = await self._day_transcript(session, user_id=user.id, note_date=target_date)
            items = await daily_note_items_or_fallback(
                api_key=self._settings.aliyun_api_key,
                model=self._settings.text_model,
                transcript=transcript,
                base_url=self._settings.aliyun_compatible_base_url,
            )
            if not items:
                note.status = DailyNoteStatus.EMPTY.value
                note.items_json = []
                note.body_text = ""
                note.shared_at = None
                await session.execute(
                    delete(DailyNoteImage).where(DailyNoteImage.daily_note_id == note.id)
                )
                await session.commit()
                await session.refresh(note)
                return await self._response_with_images(session, note)

            note.items_json = items
            note.body_text = "\n".join(items)
            note.status = DailyNoteStatus.READY.value
            await session.execute(
                delete(DailyNoteImage).where(DailyNoteImage.daily_note_id == note.id)
            )
            await session.commit()

            await self._generate_and_store_images(
                session, note=note, items=items, gender=user.gender
            )

            if settings.share_to_child_enabled:
                await self._share_to_child(session, parent=user, note=note)
            else:
                note.shared_at = None
                note.share_error = None
                await session.commit()

            await session.refresh(note)
            return await self._response_with_images(session, note)
        except AppError:
            note.status = DailyNoteStatus.FAILED.value
            await session.commit()
            raise
        except Exception:
            logger.exception("daily_note_generate_failed parent_id=%s", user.id)
            note.status = DailyNoteStatus.FAILED.value
            await session.commit()
            raise AppError(
                502,
                "daily_note.generate_failed",
                "刚才没能生成每日小记。请稍后再试，已有小记没有被改丢。",
            ) from None

    async def run_auto_generate_due(
        self, session: AsyncSession, *, now: datetime | None = None
    ) -> int:
        """调度：本地时区当前小时==generate_hour 且今日尚未 auto 成功的父母。"""
        tz = ZoneInfo(self._settings.local_timezone)
        local_now = (now or datetime.now(UTC)).astimezone(tz)
        today = local_now.date()
        hour = local_now.hour

        settings_rows = (
            await session.execute(
                select(DailyNoteSettings).where(
                    DailyNoteSettings.generate_enabled.is_(True),
                    DailyNoteSettings.generate_hour == hour,
                )
            )
        ).scalars().all()

        done = 0
        for settings in settings_rows:
            existing = await session.scalar(
                select(DailyNote).where(
                    DailyNote.parent_id == settings.user_id,
                    DailyNote.note_date == today,
                    DailyNote.source == DailyNoteSource.AUTO.value,
                    DailyNote.status.in_(
                        [
                            DailyNoteStatus.READY.value,
                            DailyNoteStatus.EMPTY.value,
                            DailyNoteStatus.PENDING.value,
                        ]
                    ),
                )
            )
            if existing is not None and existing.status != DailyNoteStatus.FAILED.value:
                continue
            # 手动已成功则不再自动覆盖
            manual_ready = await session.scalar(
                select(DailyNote).where(
                    DailyNote.parent_id == settings.user_id,
                    DailyNote.note_date == today,
                    DailyNote.status == DailyNoteStatus.READY.value,
                )
            )
            if manual_ready is not None:
                continue

            parent = await session.get(User, settings.user_id)
            if parent is None or parent.role != UserRole.PARENT.value:
                continue
            try:
                # 先插 pending 占位，降低多实例重复
                await self._upsert_pending(
                    session,
                    parent_id=parent.id,
                    note_date=today,
                    source=DailyNoteSource.AUTO.value,
                )
                await self.generate_for_parent(
                    session,
                    user=parent,
                    source=DailyNoteSource.AUTO.value,
                    note_date=today,
                    respect_generate_enabled=True,
                )
                done += 1
            except Exception:
                logger.exception(
                    "daily_note_auto_failed parent_id=%s", settings.user_id
                )
        return done

    async def _response_with_images(
        self, session: AsyncSession, note: DailyNote
    ) -> DailyNoteResponse:
        images = list(
            (
                await session.execute(
                    select(DailyNoteImage)
                    .where(DailyNoteImage.daily_note_id == note.id)
                    .order_by(DailyNoteImage.seq.asc())
                )
            )
            .scalars()
            .all()
        )
        return _to_note_response(note, images)

    async def _upsert_pending(
        self,
        session: AsyncSession,
        *,
        parent_id: UUID,
        note_date: date,
        source: str,
    ) -> DailyNote:
        note = await session.scalar(
            select(DailyNote).where(
                DailyNote.parent_id == parent_id,
                DailyNote.note_date == note_date,
            )
        )
        if note is None:
            note = DailyNote(
                id=uuid4(),
                parent_id=parent_id,
                note_date=note_date,
                items_json=[],
                body_text="",
                status=DailyNoteStatus.PENDING.value,
                source=source,
            )
            session.add(note)
        else:
            note.status = DailyNoteStatus.PENDING.value
            note.source = source
            note.share_error = None
        await session.commit()
        await session.refresh(note)
        return note

    async def _day_transcript(
        self, session: AsyncSession, *, user_id: UUID, note_date: date
    ) -> str:
        day_start, day_end = _day_bounds_utc(self._settings, note_date)
        convs = (
            await session.execute(
                select(Conversation)
                .where(
                    Conversation.user_id == user_id,
                    Conversation.started_at >= day_start,
                    Conversation.started_at < day_end,
                )
                .order_by(Conversation.started_at.asc())
            )
        ).scalars().all()
        if not convs:
            return ""
        lines: list[str] = []
        for conv in convs:
            items = (
                await session.execute(
                    select(ConversationItem)
                    .where(
                        ConversationItem.conversation_id == conv.id,
                        ConversationItem.kind.in_(
                            [
                                ConversationItemKind.USER.value,
                                ConversationItemKind.ASSISTANT.value,
                            ]
                        ),
                    )
                    .order_by(ConversationItem.seq.asc())
                )
            ).scalars().all()
            for item in items:
                text = (item.text or "").strip()
                if not text:
                    continue
                role = "用户" if item.kind == ConversationItemKind.USER.value else "可可"
                lines.append(f"{role}：{text}")
            if len("\n".join(lines)) > 8000:
                break
        return "\n".join(lines)[:8000]

    async def _generate_and_store_images(
        self,
        session: AsyncSession,
        *,
        note: DailyNote,
        items: list[str],
        gender: str,
    ) -> None:
        key = self._settings.aliyun_api_key
        if key is None or not key.get_secret_value().strip():
            await record_llm_trace(
                purpose=PURPOSE_IMAGE_GENERATE,
                modality="image",
                model=self._settings.image_model,
                status="skipped",
                user_id=note.parent_id,
                error_message="未配置 API Key，每日小记跳过配图",
            )
            return

        scenes = items[:2]
        elder = _elder_look(gender)
        tokens = bind_llm_trace(user_id=note.parent_id)
        try:
            client = WanImageClient(
                api_key=key,
                model=self._settings.image_model,
                base_url=self._settings.aliyun_http_base_url,
            )
            for seq, scene in enumerate(scenes):
                prompt = (
                    f"温馨插画，{_COCO_LOOK}，与{elder}在一起，场景：{scene}。"
                    "中国家庭日常氛围，柔和暖色，无文字无水印。"
                )[:_PROMPT_MAX]
                try:
                    result = await client.generate(
                        prompt=prompt,
                        n=1,
                        watermark=False,
                        size="1280*1280",
                    )
                    if not result.images:
                        continue
                    raw, mime = await _download_image(result.images[0].url)
                    if len(raw) > _IMAGE_MAX_BYTES:
                        logger.warning(
                            "daily_note_image_too_large note_id=%s size=%s",
                            note.id,
                            len(raw),
                        )
                        continue
                    session.add(
                        DailyNoteImage(
                            id=uuid4(),
                            daily_note_id=note.id,
                            seq=seq,
                            mime_type=mime,
                            data=raw,
                            prompt=prompt,
                        )
                    )
                    await session.commit()
                except Exception:
                    logger.warning(
                        "daily_note_image_failed note_id=%s seq=%s",
                        note.id,
                        seq,
                        exc_info=True,
                    )
        finally:
            reset_llm_trace(tokens)

    async def _share_to_child(
        self, session: AsyncSession, *, parent: User, note: DailyNote
    ) -> None:
        family = await session.scalar(
            select(Family).where(
                Family.parent_user_id == parent.id,
                Family.status == FamilyStatus.ACTIVE.value,
                Family.child_user_id.is_not(None),
            )
        )
        if family is None or family.child_user_id is None:
            note.share_error = "未绑定子女"
            note.shared_at = None
            await session.commit()
            return

        for attempt in range(2):
            try:
                note.shared_at = datetime.now(UTC)
                note.share_error = None
                title = f"{parent.display_name}的今日小记已更新"
                session.add(
                    Notification(
                        user_id=family.child_user_id,
                        type=NotificationType.CARE_MESSAGE.value,
                        title=title,
                        body="可可整理了今天聊到的几件小事",
                        payload={
                            "daily_note_id": str(note.id),
                            "kind": "daily_note",
                        },
                    )
                )
                await session.commit()
                return
            except Exception:
                logger.warning(
                    "daily_note_share_failed attempt=%s note_id=%s",
                    attempt,
                    note.id,
                    exc_info=True,
                )
                if attempt == 1:
                    note.shared_at = None
                    note.share_error = "发送失败"
                    await session.commit()

    async def _assert_can_view_note(
        self, session: AsyncSession, *, user: User, note: DailyNote
    ) -> None:
        if user.role == UserRole.PARENT.value and note.parent_id == user.id:
            return
        if user.role == UserRole.CHILD.value and note.shared_at is not None:
            family = await session.scalar(
                select(Family).where(
                    Family.child_user_id == user.id,
                    Family.parent_user_id == note.parent_id,
                    Family.status == FamilyStatus.ACTIVE.value,
                )
            )
            if family is not None:
                return
        raise AppError(403, "daily_note.forbidden", "没有权限查看这张配图。")


async def _download_image(url: str) -> tuple[bytes, str]:
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.get(url)
        response.raise_for_status()
        content_type = response.headers.get("content-type", "image/png")
        mime = content_type.split(";")[0].strip() or "image/png"
        return response.content, mime
