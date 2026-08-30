"""每日小记 BOS 配图：mock 存储，不打外网。"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from pydantic import SecretStr

from coco.config import Settings
from coco.errors import AppError
from coco.models.daily_note import DailyNote, DailyNoteImage, DailyNoteStatus
from coco.models.user import User, UserRole, UserStatus
from coco.modules.daily_notes.service import DailyNoteService
from coco.providers.bos_storage import BosPutResult


def _parent_user() -> User:
    return User(
        id=uuid4(),
        phone_hash="h",
        phone_masked="138****0000",
        phone_e164="+8613800000000",
        display_name="测试",
        role=UserRole.PARENT.value,
        status=UserStatus.ACTIVE.value,
    )


def _settings(**kwargs: object) -> Settings:
    base = dict(
        bos_access_key_id=SecretStr("test-ak"),
        bos_secret_access_key=SecretStr("test-sk"),
        bos_endpoint="https://bj.bcebos.com",
        bos_bucket="coco-oss",
        bos_url_ttl_seconds=600,
    )
    base.update(kwargs)
    return Settings(**base)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_response_with_images_returns_presigned_url(monkeypatch: pytest.MonkeyPatch) -> None:
    service = DailyNoteService(_settings())
    bos = MagicMock()
    bos.presigned_url = AsyncMock(return_value="https://signed.example/a.png")
    monkeypatch.setattr(service, "_require_bos", lambda: bos)

    note_id = uuid4()
    image_id = uuid4()
    from datetime import UTC, date, datetime

    note = DailyNote(
        id=note_id,
        parent_id=uuid4(),
        note_date=date.today(),
        title="散步",
        header_line="",
        items_json=["散步"],
        body_text="散步",
        closing="",
        extraction_json={},
        status=DailyNoteStatus.READY.value,
        source="manual",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    img = DailyNoteImage(
        id=image_id,
        daily_note_id=note_id,
        seq=0,
        mime_type="image/png",
        object_key=f"daily-notes/{note.parent_id}/{note_id}/{image_id}",
    )

    session = AsyncMock()
    # session.execute(...).scalars().all()
    result = MagicMock()
    result.scalars.return_value.all.return_value = [img]
    session.execute = AsyncMock(return_value=result)

    resp = await service._response_with_images(session, note)
    assert len(resp.images) == 1
    assert resp.images[0].url == "https://signed.example/a.png"
    bos.presigned_url.assert_awaited()


@pytest.mark.asyncio
async def test_upload_parent_photo_puts_bos_and_sets_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = DailyNoteService(_settings())
    bos = MagicMock()
    bos.put_bytes = AsyncMock(return_value=BosPutResult(key="k", etag=None, url="https://x"))
    bos.presigned_url = AsyncMock(return_value="https://signed.example/photo.jpg")
    monkeypatch.setattr(service, "_require_bos", lambda: bos)

    user = _parent_user()
    settings_row = SimpleNamespace(
        user_id=user.id,
        generate_enabled=True,
        share_to_child_enabled=False,
        generate_hour=20,
        parent_photo_object_key=None,
        parent_photo_mime=None,
    )

    async def _get_or_create(session, *, user):  # noqa: ANN001
        return settings_row

    monkeypatch.setattr(service, "get_or_create_settings", _get_or_create)

    session = AsyncMock()
    session.commit = AsyncMock()
    session.refresh = AsyncMock()

    resp = await service.upload_parent_photo(
        session,
        user=user,
        data=b"fake-jpeg",
        mime_type="image/jpeg",
    )
    assert settings_row.parent_photo_object_key == f"daily-notes/{user.id}/parent-photo"
    assert settings_row.parent_photo_mime == "image/jpeg"
    assert resp.has_parent_photo is True
    assert resp.parent_photo_url == "https://signed.example/photo.jpg"
    bos.put_bytes.assert_awaited()


@pytest.mark.asyncio
async def test_upload_parent_photo_requires_bos() -> None:
    service = DailyNoteService(
        Settings(
            bos_access_key_id=None,
            bos_secret_access_key=None,
            bos_bucket="coco-oss",
        )
    )
    user = _parent_user()
    with pytest.raises(AppError) as exc:
        await service.upload_parent_photo(
            AsyncMock(),
            user=user,
            data=b"x",
            mime_type="image/jpeg",
        )
    assert exc.value.code == "bos.not_configured"
