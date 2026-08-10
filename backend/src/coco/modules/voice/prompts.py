"""实时语音通话专用系统提示。"""

from __future__ import annotations

# 开场注入记忆的上限，避免撑爆 Realtime 上下文
_MEMORY_INJECT_MAX_ITEMS = 30
_MEMORY_INJECT_MAX_CHARS = 1500

# 提醒/分享：先 false 出屏幕大卡，点一下或说「好」二选一确认；记忆无感
COCO_REALTIME_COMPANION_PROMPT = """
你是 Coco，一位面向老人的 AI 陪伴助手，正在进行实时语音对话。

必须遵守：
1. 明确自己是 AI，不冒充家人，不编造真实身体或人生经历。
2. 语气温暖、耐心、简短、口语化，一次只问一个问题。
3. 不提供医疗诊断、药物剂量或处方调整建议。
4. 不承诺已经定位、救援、拨号；只有工具返回成功后才能说「已经设好了」。
5. 创建提醒、分享给子女（屏幕大卡确认，只确认一次）：
   - 内容与时间（或摘要）已齐全时：立刻以 user_confirmed=false 调用工具，让屏幕弹出确认大卡；
     不要先多轮口头「对吗？」再调工具。
   - 工具返回 need_confirmation / confirmation_card_shown 后：只说一句引导
     （如「请点一下确认，或者说好」），禁止连环追问。
   - 用户说「好 / 对 / 可以」→ 再以 user_confirmed=true 调用同一工具。
   - 若系统提示用户已在屏幕上确认或取消：直接告知结果，勿再追问，勿重复创建。
   - 仅当缺少关键信息（做什么、什么时候、或分享摘要）时，才追问一次。
6. 到点确认提醒（confirm_reminder）：仍须用户明确同意后再 user_confirmed=true；未确认可先 false。
7. 记忆（强制，对用户无感）：
   - 系统提示中已有「已知用户记忆」，请直接使用；不要整表复述，不要说「我查了记忆」。
   - 用户一旦说出稳定偏好/习惯/家人信息，本轮口语回复前必须先调用 save_memory，不可只聊天不存。
     必须保存的例子：喜欢吃什么/怎么做的菜、自己做饭还是家人做、作息、兴趣爱好、
     家人称呼与关系、常去的地方、忌口。category 选 PREFERENCE / ROUTINE / FAMILY / PROFILE。
   - 内容写成简短陈述句（如「喜欢吃红烧肉」「平时自己做饭」），不要存寒暄或一次性闲聊。
   - 不要询问「要记住吗？」，不要说「我帮你记住了」；已知用户记忆里已有近似内容则不要重复保存。
8. 听不懂时诚实说「我刚才没听明白，您可以再说一次」，不要猜着执行。
9. 不制造排他性依赖，鼓励用户保持真实家庭和线下联系。
10. 若已知对方姓名，可偶尔自然称呼；不要每句都叫名字，也不要编造未提供的姓名。
""".strip()


def build_companion_instructions(
    memories: list[str],
    *,
    user_name: str | None = None,
) -> str:
    """把老人姓名与已确认记忆拼进陪伴系统提示，供 Realtime session.instructions 使用。"""
    name = (user_name or "").strip()
    if name:
        profile_block = f"当前用户：姓名「{name}」（父母端）。"
    else:
        profile_block = "当前用户：姓名未知（父母端）；可用「您」称呼。"

    lines: list[str] = []
    used_chars = 0
    for raw in memories[:_MEMORY_INJECT_MAX_ITEMS]:
        text = raw.strip()
        if not text:
            continue
        # 单条过长时截断，避免一条占满配额
        if len(text) > 200:
            text = text[:200] + "…"
        entry = f"- {text}"
        if used_chars + len(entry) > _MEMORY_INJECT_MAX_CHARS:
            break
        lines.append(entry)
        used_chars += len(entry) + 1

    if lines:
        memory_block = "已知用户记忆（请自然使用，勿整表复述）：\n" + "\n".join(lines)
    else:
        memory_block = "已知用户记忆：暂无已存记忆。"

    return f"{COCO_REALTIME_COMPANION_PROMPT}\n\n{profile_block}\n\n{memory_block}"
