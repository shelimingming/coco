"""每日小记：按日生成图文、设置门禁、条件分享给子女；配图存百度 BOS。"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from coco.config import Settings
from coco.database import get_session_factory
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
from coco.providers.bos_storage import BosStorage, get_bos_storage
from coco.providers.image_compress import compress_for_daily_note
from coco.providers.qwen_text import (
    build_daily_note_header_line,
    daily_note_empty_guidance,
    diary_paragraphs,
    extract_daily_note_or_fallback,
    extraction_has_diary_material,
    write_daily_note_or_fallback,
)
from coco.providers.wan_image import WanImageClient

logger = logging.getLogger(__name__)

_PROMPT_MAX = 500
# 每日小记配图上限（与撰写 prompt、前端图文对应一致）
_DAILY_NOTE_MAX_IMAGES = 2
_IMAGE_MAX_BYTES = 4 * 1024 * 1024
_PARENT_PHOTO_MAX_BYTES = 3 * 1024 * 1024
_IMAGE_STYLE_PREFIX = "温馨手绘水彩插画，柔和暖色调，画面明亮干净，留白多，治愈系，光线温暖"
_IMAGE_NEGATIVE = "文字,水印,标题,字幕,照片写实,阴郁,恐怖,血腥,畸形手指"
# 无参考照时固定女性人物卡（配图外观不跟性别开关）
_DEFAULT_ELDER_LOOK = "一位慈祥的中国老年女性，花白短发，温和微笑，日常家居服装"
_TRANSCRIPT_MIN_CHARS = 8
# 进程内去重：同一父母同一天避免叠多个后台任务
_generate_inflight: set[tuple[UUID, date]] = set()


def _elder_look_for_image(*, has_parent_photo: bool) -> str:
    """有参考照时不写外貌文案；无照默认女性。"""
    if has_parent_photo:
        return ""
    return _DEFAULT_ELDER_LOOK


def _to_data_uri(data: bytes, mime: str) -> str:
    import base64

    b64 = base64.b64encode(data).decode("ascii")
    return f"data:{mime};base64,{b64}"


def _local_today(settings: Settings) -> date:
    return datetime.now(ZoneInfo(settings.local_timezone)).date()


def _day_bounds_utc(settings: Settings, note_date: date) -> tuple[datetime, datetime]:
    tz = ZoneInfo(settings.local_timezone)
    start_local = datetime(note_date.year, note_date.month, note_date.day, tzinfo=tz)
    end_local = start_local + timedelta(days=1)
    return start_local.astimezone(UTC), end_local.astimezone(UTC)


def _parent_photo_key(user_id: UUID) -> str:
    return f"daily-notes/{user_id}/parent-photo"


def _note_image_key(*, parent_id: UUID, note_id: UUID, image_id: UUID) -> str:
    return f"daily-notes/{parent_id}/{note_id}/{image_id}"


class DailyNoteService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def _require_bos(self) -> BosStorage:
        if not self._settings.bos_available:
            raise AppError(
                503,
                "bos.not_configured",
                "对象存储未配置，暂时无法处理图片。请稍后再试，文字小记不受影响。",
            )
        # 复用进程内客户端，并确保桶已开 Web 读 CORS
        return get_bos_storage()

    async def _presign(self, bos: BosStorage, key: str) -> str:
        return await bos.presigned_url(
            key,
            expiration_seconds=max(60, self._settings.bos_url_ttl_seconds),
        )

    async def get_or_create_settings(
        self, session: AsyncSession, *, user: User
    ) -> DailyNoteSettings:
        row = await session.get(DailyNoteSettings, user.id)
        if row is None:
            row = DailyNoteSettings(
                user_id=user.id,
                generate_enabled=False,
                share_to_child_enabled=False,
                generate_hour=20,
            )
            session.add(row)
            await session.commit()
            await session.refresh(row)
        return row

    async def get_settings(self, session: AsyncSession, *, user: User) -> DailyNoteSettingsResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以管理每日小记。")
        settings = await self.get_or_create_settings(session, user=user)
        gender = (
            user.gender
            if user.gender in {g.value for g in UserGender}
            else UserGender.UNKNOWN.value
        )
        key = settings.parent_photo_object_key
        has_photo = bool(key)
        photo_url: str | None = None
        if has_photo and key:
            bos = self._require_bos()
            photo_url = await self._presign(bos, key)
        return DailyNoteSettingsResponse(
            generate_enabled=settings.generate_enabled,
            share_to_child_enabled=settings.share_to_child_enabled,
            generate_hour=settings.generate_hour,
            gender=gender,  # type: ignore[arg-type]
            has_parent_photo=has_photo,
            parent_photo_url=photo_url,
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

    async def upload_parent_photo(
        self,
        session: AsyncSession,
        *,
        user: User,
        data: bytes,
        mime_type: str,
    ) -> DailyNoteSettingsResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以上传参考照。")
        cleaned_mime = (mime_type or "").split(";")[0].strip().lower() or "image/jpeg"
        if cleaned_mime not in {"image/jpeg", "image/png", "image/webp"}:
            raise AppError(
                400,
                "daily_note.photo_type",
                "请上传 JPG、PNG 或 WebP 照片。数据没有写入。",
            )
        if not data:
            raise AppError(400, "daily_note.photo_empty", "没有读到照片，请再选一张。")
        if len(data) > _PARENT_PHOTO_MAX_BYTES:
            raise AppError(
                400,
                "daily_note.photo_too_large",
                "照片太大了，请选一张更小的（约 3MB 以内）。数据没有写入。",
            )
        bos = self._require_bos()
        settings = await self.get_or_create_settings(session, user=user)
        key = _parent_photo_key(user.id)
        await bos.put_bytes(key, data, content_type=cleaned_mime)
        settings.parent_photo_object_key = key
        settings.parent_photo_mime = cleaned_mime
        await session.commit()
        return await self.get_settings(session, user=user)

    async def delete_parent_photo(
        self, session: AsyncSession, *, user: User
    ) -> DailyNoteSettingsResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "daily_note.parent_required", "只有老人模式可以管理参考照。")
        settings = await self.get_or_create_settings(session, user=user)
        old_key = settings.parent_photo_object_key
        settings.parent_photo_object_key = None
        settings.parent_photo_mime = None
        await session.commit()
        if old_key and self._settings.bos_available:
            try:
                await self._require_bos().delete(old_key)
            except Exception:
                logger.warning(
                    "daily_note_parent_photo_bos_delete_failed key=%s", old_key, exc_info=True
                )
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
                    [
                        DailyNoteStatus.READY.value,
                        DailyNoteStatus.EMPTY.value,
                        DailyNoteStatus.PENDING.value,
                    ]
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

    async def child_today(self, session: AsyncSession, *, user: User) -> DailyNoteResponse | None:
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

    async def enqueue_generate_for_parent(
        self,
        session: AsyncSession,
        *,
        user: User,
        source: str = DailyNoteSource.MANUAL.value,
        note_date: date | None = None,
        respect_generate_enabled: bool = True,
    ) -> DailyNoteResponse:
        """立刻落 pending 并后台跑完整管线，HTTP 不等 LLM/生图。"""
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
        # pending 态无配图，避免误触 BOS
        note.title = ""
        note.header_line = build_daily_note_header_line(target_date)
        note.items_json = []
        note.body_text = ""
        note.closing = ""
        await session.commit()
        await session.refresh(note)
        response = await self._response_with_images(session, note)

        job_key = (user.id, target_date)
        if job_key in _generate_inflight:
            return response

        _generate_inflight.add(job_key)
        user_id = user.id
        settings_snapshot = self._settings

        async def _background() -> None:
            try:
                factory = get_session_factory()
                async with factory() as bg_session:
                    parent = await bg_session.get(User, user_id)
                    if parent is None or parent.role != UserRole.PARENT.value:
                        return
                    await DailyNoteService(settings_snapshot).generate_for_parent(
                        bg_session,
                        user=parent,
                        source=source,
                        note_date=target_date,
                        respect_generate_enabled=respect_generate_enabled,
                    )
            except Exception:
                logger.exception(
                    "daily_note_background_failed parent_id=%s date=%s",
                    user_id,
                    target_date,
                )
            finally:
                _generate_inflight.discard(job_key)

        task = asyncio.create_task(
            _background(),
            name=f"daily-note-generate-{user_id}-{target_date.isoformat()}",
        )
        # 测试环境：等后台跑完再返回终态，避免残留 task 干扰下一条用例
        if settings_snapshot.environment == "test":
            await task
            factory = get_session_factory()
            async with factory() as settled_session:
                settled = await settled_session.get(DailyNote, note.id)
                if settled is not None:
                    return await self._response_with_images(settled_session, settled)
        return response

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
            extraction = await extract_daily_note_or_fallback(
                api_key=self._settings.aliyun_api_key,
                model=self._settings.text_model,
                transcript=transcript,
                base_url=self._settings.aliyun_compatible_base_url,
            )
            material_ok = len(
                transcript.strip()
            ) >= _TRANSCRIPT_MIN_CHARS and extraction_has_diary_material(extraction)
            if not material_ok:
                # 素材不足：引导再聊，不硬写假日记、不配图、不分享
                note.status = DailyNoteStatus.EMPTY.value
                note.title = ""
                note.header_line = build_daily_note_header_line(target_date)
                note.items_json = []
                note.body_text = daily_note_empty_guidance()
                note.closing = ""
                note.extraction_json = extraction
                note.shared_at = None
                note.share_error = None
                await self._delete_note_images(session, note=note)
                await session.commit()
                await session.refresh(note)
                return await self._response_with_images(session, note)

            recent = await self._recent_diary_snippets(
                session, parent_id=user.id, before_date=target_date, limit=5
            )
            diary = await write_daily_note_or_fallback(
                api_key=self._settings.aliyun_api_key,
                model=self._settings.text_model,
                extraction=extraction,
                recent_diaries=recent,
                display_name=user.display_name or "",
                transcript=transcript,
                base_url=self._settings.aliyun_compatible_base_url,
            )
            paragraphs = diary_paragraphs(str(diary.get("body") or ""))
            if not paragraphs:
                note.status = DailyNoteStatus.EMPTY.value
                note.title = ""
                note.header_line = build_daily_note_header_line(target_date)
                note.items_json = []
                note.body_text = daily_note_empty_guidance()
                note.closing = ""
                note.extraction_json = extraction
                note.shared_at = None
                note.share_error = None
                await self._delete_note_images(session, note=note)
                await session.commit()
                await session.refresh(note)
                return await self._response_with_images(session, note)

            weather = ""
            if isinstance(extraction.get("weather_mentioned"), str):
                weather = extraction["weather_mentioned"]
            note.title = str(diary.get("title") or "").strip()[:64]
            note.header_line = build_daily_note_header_line(target_date, weather_mentioned=weather)
            note.items_json = paragraphs
            note.body_text = "\n".join(paragraphs)
            note.closing = str(diary.get("closing") or "").strip()[:200]
            note.extraction_json = extraction
            note.status = DailyNoteStatus.READY.value
            await self._delete_note_images(session, note=note)
            await session.commit()

            # 生图前再读设置；画面严格跟日记段落/illustrations 对齐，不另造情节
            settings = await self.get_or_create_settings(session, user=user)
            illustrations = diary.get("illustrations") if isinstance(diary, dict) else None
            scenes = _aligned_scenes(illustrations, paragraphs)
            await self._generate_and_store_images(
                session,
                note=note,
                scenes=scenes,
                settings=settings,
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
            (
                await session.execute(
                    select(DailyNoteSettings).where(
                        DailyNoteSettings.generate_enabled.is_(True),
                        DailyNoteSettings.generate_hour == hour,
                    )
                )
            )
            .scalars()
            .all()
        )

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
                logger.exception("daily_note_auto_failed parent_id=%s", settings.user_id)
        return done

    async def _response_with_images(
        self, session: AsyncSession, note: DailyNote
    ) -> DailyNoteResponse:
        images = list(
            (
                await session.execute(
                    select(DailyNoteImage)
                    .options(
                        load_only(
                            DailyNoteImage.id,
                            DailyNoteImage.daily_note_id,
                            DailyNoteImage.seq,
                            DailyNoteImage.mime_type,
                            DailyNoteImage.object_key,
                        )
                    )
                    .where(DailyNoteImage.daily_note_id == note.id)
                    .order_by(DailyNoteImage.seq.asc())
                )
            )
            .scalars()
            .all()
        )
        items = note.items_json if isinstance(note.items_json, list) else []
        str_items = [str(x) for x in items if isinstance(x, str) and x.strip()]
        metas: list[DailyNoteImageMeta] = []
        if images:
            bos = self._require_bos()
            for img in sorted(images, key=lambda i: i.seq):
                metas.append(
                    DailyNoteImageMeta(
                        id=img.id,
                        seq=img.seq,
                        mime_type=img.mime_type,
                        url=await self._presign(bos, img.object_key),
                    )
                )
        return DailyNoteResponse(
            id=note.id,
            note_date=note.note_date,
            title=note.title or "",
            header_line=note.header_line or "",
            items=str_items,
            body_text=note.body_text or "\n".join(str_items),
            closing=note.closing or "",
            status=note.status,
            source=note.source,
            shared_at=note.shared_at,
            images=metas,
            created_at=note.created_at,
        )

    async def _delete_note_images(self, session: AsyncSession, *, note: DailyNote) -> None:
        """删库前先清 BOS，避免孤儿对象。"""
        rows = list(
            (
                await session.execute(
                    select(DailyNoteImage)
                    .options(load_only(DailyNoteImage.id, DailyNoteImage.object_key))
                    .where(DailyNoteImage.daily_note_id == note.id)
                )
            )
            .scalars()
            .all()
        )
        if rows and self._settings.bos_available:
            bos = self._require_bos()
            for row in rows:
                try:
                    await bos.delete(row.object_key)
                except Exception:
                    logger.warning(
                        "daily_note_image_bos_delete_failed key=%s",
                        row.object_key,
                        exc_info=True,
                    )
        await session.execute(delete(DailyNoteImage).where(DailyNoteImage.daily_note_id == note.id))

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
                title="",
                header_line="",
                items_json=[],
                body_text="",
                closing="",
                extraction_json={},
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

    async def _recent_diary_snippets(
        self,
        session: AsyncSession,
        *,
        parent_id: UUID,
        before_date: date,
        limit: int = 5,
    ) -> list[str]:
        """近几篇 ready 日记正文，供撰写防重复。"""
        rows = (
            (
                await session.execute(
                    select(DailyNote)
                    .where(
                        DailyNote.parent_id == parent_id,
                        DailyNote.note_date < before_date,
                        DailyNote.status == DailyNoteStatus.READY.value,
                    )
                    .order_by(DailyNote.note_date.desc())
                    .limit(limit)
                )
            )
            .scalars()
            .all()
        )
        snippets: list[str] = []
        for row in rows:
            title = (row.title or "").strip()
            body = (row.body_text or "").strip()
            if not body:
                continue
            head = f"「{title}」\n{body}" if title else body
            snippets.append(head[:400])
        return snippets

    async def _day_transcript(
        self, session: AsyncSession, *, user_id: UUID, note_date: date
    ) -> str:
        day_start, day_end = _day_bounds_utc(self._settings, note_date)
        convs = (
            (
                await session.execute(
                    select(Conversation)
                    .where(
                        Conversation.user_id == user_id,
                        Conversation.started_at >= day_start,
                        Conversation.started_at < day_end,
                    )
                    .order_by(Conversation.started_at.asc())
                )
            )
            .scalars()
            .all()
        )
        if not convs:
            return ""
        lines: list[str] = []
        for conv in convs:
            items = (
                (
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
                )
                .scalars()
                .all()
            )
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
        scenes: list[str],
        settings: DailyNoteSettings,
    ) -> None:
        key = self._settings.aliyun_api_key
        if self._settings.environment == "test":
            # 集成测试只验文本管线，跳过外网生图
            return
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
        if not scenes:
            return

        from coco.assets import load_coco_reference_png

        try:
            coco_bytes = load_coco_reference_png()
        except Exception:
            logger.exception("daily_note_coco_reference_missing")
            return

        refs: list[str] = [_to_data_uri(coco_bytes, "image/png")]
        parent_key = settings.parent_photo_object_key
        has_parent_photo = bool(parent_key)
        if has_parent_photo and parent_key:
            try:
                bos = self._require_bos()
                photo = await bos.get_bytes(parent_key)
                mime = settings.parent_photo_mime or "image/jpeg"
                refs.append(_to_data_uri(photo, mime))
            except Exception:
                logger.warning(
                    "daily_note_parent_photo_load_failed key=%s",
                    parent_key,
                    exc_info=True,
                )
                has_parent_photo = False

        elder = _elder_look_for_image(has_parent_photo=has_parent_photo)
        tokens = bind_llm_trace(user_id=note.parent_id)
        try:
            client = WanImageClient(
                api_key=key,
                model=self._settings.image_model,
                base_url=self._settings.aliyun_http_base_url,
            )
            bos = self._require_bos()
            # 每天最多 _DAILY_NOTE_MAX_IMAGES 张；seq 与正文段落下标对齐，便于前端图文对应
            for seq, scene in enumerate(scenes[:_DAILY_NOTE_MAX_IMAGES]):
                if has_parent_photo:
                    prompt = (
                        f"{_IMAGE_STYLE_PREFIX}。"
                        f"图1是金毛小狗可可的形象参考，图2是老人的照片参考，"
                        f"人物外观必须严格与图2照片一致，不要改年龄发型衣着。"
                        f"请只画下列场景，禁止添加场景里没有的情节或地点："
                        f"「{scene}」。无文字无水印。"
                    )
                else:
                    prompt = (
                        f"{_IMAGE_STYLE_PREFIX}。"
                        f"图1是金毛小狗可可的形象参考，请保持其外观一致。"
                        f"请画可可与{elder}，只表现下列场景，禁止添加场景里没有的情节或地点："
                        f"「{scene}」。无文字无水印。"
                    )
                prompt = prompt[:_PROMPT_MAX]
                try:
                    result = await client.generate(
                        prompt=prompt,
                        n=1,
                        watermark=False,
                        size="1K",
                        reference_images=refs,
                        negative_prompt=_IMAGE_NEGATIVE,
                    )
                    if not result.images:
                        continue
                    raw, _mime = await _download_image(result.images[0].url)
                    # 万相默认 PNG 约 1.8～2.2MB；转 JPEG 后再上传 BOS
                    raw, mime = compress_for_daily_note(raw)
                    if len(raw) > _IMAGE_MAX_BYTES:
                        logger.warning(
                            "daily_note_image_too_large note_id=%s size=%s",
                            note.id,
                            len(raw),
                        )
                        continue
                    image_id = uuid4()
                    object_key = _note_image_key(
                        parent_id=note.parent_id,
                        note_id=note.id,
                        image_id=image_id,
                    )
                    await bos.put_bytes(object_key, raw, content_type=mime)
                    session.add(
                        DailyNoteImage(
                            id=image_id,
                            daily_note_id=note.id,
                            seq=seq,
                            mime_type=mime,
                            object_key=object_key,
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


def _aligned_scenes(illustrations: object, paragraphs: list[str]) -> list[str]:
    """配图与正文段一一对应：优先 illustrations[i]，否则用该段原文。"""
    illust: list[str] = []
    if isinstance(illustrations, list):
        for item in illustrations:
            if isinstance(item, str) and item.strip():
                illust.append(item.strip()[:100])
    scenes: list[str] = []
    for i, para in enumerate(paragraphs[:_DAILY_NOTE_MAX_IMAGES]):
        if i < len(illust):
            scenes.append(illust[i])
        elif para.strip():
            # 用段落本身作画面说明，保证图文同源
            scenes.append(para.strip()[:100])
    if not scenes and illust:
        scenes = illust[:_DAILY_NOTE_MAX_IMAGES]
    return scenes[:_DAILY_NOTE_MAX_IMAGES]


async def _download_image(url: str) -> tuple[bytes, str]:
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.get(url)
        response.raise_for_status()
        content_type = response.headers.get("content-type", "image/png")
        mime = content_type.split(";")[0].strip() or "image/png"
        return response.content, mime
