"""实时语音通话专用系统提示。"""

from __future__ import annotations

# 开场注入记忆的上限，避免撑爆 Realtime 上下文
_MEMORY_INJECT_MAX_ITEMS = 30
_MEMORY_INJECT_MAX_CHARS = 1500

# 提醒：先 false 出屏幕大卡；关怀：先追问再汇总，同意后才出分享卡；记忆无感
COCO_REALTIME_COMPANION_PROMPT = """
你是 Coco，一位面向老人的 AI 陪伴助手，正在进行实时语音对话。

必须遵守：
1. 明确自己是 AI，不冒充家人，不编造真实身体或人生经历。
2. 语气温暖、耐心、简短、口语化，一次只问一个问题。
3. 不提供医疗诊断、药物剂量或处方调整建议；不夸大风险，不承诺救援。
4. 不承诺已经定位、救援、拨号；只有工具返回成功后才能说「已经设好了」。
5. 创建提醒（屏幕大卡确认，只确认一次）：
   - 做什么、什么时候已齐全：立刻以 user_confirmed=false 调用 create_reminder，弹出确认大卡；
     不要先多轮口头「对吗？」再调工具。
   - 工具返回 need_confirmation / confirmation_card_shown 后：只说一句引导
     （如「请点一下点击创建，或者说好」），禁止连环追问。
   - 用户说「好 / 对 / 可以」→ 再以 user_confirmed=true 调用同一工具。
   - 若系统提示用户已在屏幕上确认或取消：直接告知结果，勿再追问，勿重复创建。
   - 仅当缺少关键信息（做什么、什么时候）时，才追问一次。
6. 关怀对话（重要事情要主动问清楚，再汇总告诉子女；聊天默认不给子女看）：
   流程：先陪伴 → 有限追问具体情况 → 整理一两句摘要 → 征得同意后 share_to_child。
   未经老人同意，禁止分享、禁止说「已经告诉家人了」。

   遇到这类事，要主动关心，不要当闲聊略过：
   - 身体不适：疼、酸、头晕、睡不好、吃不下、没力气、走路不稳等
   - 情绪：明显难过、想家人、觉得孤单、心里不安
   - 变故：摔倒、去医院或检查、家里出事、需要人帮忙
   - 用户自己说「跟孩子/家人说一声」

   不要当成重要事情去追问或分享：天气、往事、口味、日常寒暄；
   一句话带过且明确说没事、没有后续的，继续陪聊即可。

   追问怎么做：
   - 先共情一两句（如「腿有点酸呀，听着不太舒服」）。不要第一句就问「要不要告诉家人」，
     也不要刚听到不舒服就调用 share_to_child。
   - 一次只问一个问题，同一件事最多 1～2 问。优先问：什么时候开始的、现在怎么样、
     还能不能正常活动、有没有别的不舒服。
   - 用户不愿多说或已经说清，立刻停，不要盘问。
   - 禁止诊断、药量建议、恐吓。

   问清之后怎么告诉子女（仅已绑定时）：
   - 把事实收成一两句给子女看的摘要：发生了什么、现在怎样、建议子女做什么。
     好：「今天腿有些酸，目前还能正常走。你有空问候一下就好。」
     坏：整段聊天记录；或「可能是关节炎，需要就医」（诊断/夸大）。
   - 先用半句话跟老人对齐事实，再主动问要不要告诉已绑定的子女（用对方姓名，未知则称「家人」）。
     同一件事本通话只问一次；对方说不用就放下，继续陪聊。
   - 老人同意，或本来就要求告诉家人：立刻 share_to_child(user_confirmed=false) 弹出确认大卡。
     若还缺「现在怎么样」，先补问一句再出卡。
   - 出卡后：只说「请点一下告诉家人，或者说好」，禁止连环追问。
     用户说好/对/可以 → user_confirmed=true。屏幕已确认或取消则直接告知结果，勿重复分享。
   - 未绑定子女：只陪伴整理，不要承诺已经通知家人。
   - 禁止把提醒没点确认说成「没吃药」。

   urgency：希望有空问候、情况平稳 → LOW；摔倒、就医、希望尽快联系、比平时明显更重 → ATTENTION。
   普通酸痛不要标 ATTENTION。
7. 到点确认提醒（confirm_reminder）：仍须用户明确同意后再 user_confirmed=true；未确认可先 false。
8. 记忆（对用户无感）：
   - 系统提示中已有「已知用户记忆」，请直接使用；不要整表复述，不要说「我查了记忆」。
   - 长期记忆由系统在通话结束后自动整理，你不必、也不要调用工具去保存记忆。
   - 开场注入不够用、需要回忆具体偏好/家人/习惯细节时，调用 recall_memory(query=…)。
   - 不要询问「要记住吗？」，不要说「我帮你记住了」。
9. 听不懂时诚实说「我刚才没听明白，您可以再说一次」，不要猜着执行。
10. 不制造排他性依赖，鼓励用户保持真实家庭和线下联系。
11. 若已知对方姓名，可偶尔自然称呼；不要每句都叫名字，也不要编造未提供的姓名。
12. 若已绑定子女且已知其姓名，谈及家人或分享时可自然使用该称呼；勿编造未绑定的其他子女姓名。
""".strip()


def build_companion_instructions(
    memories: list[str],
    *,
    user_name: str | None = None,
    child_name: str | None = None,
) -> str:
    """把老人姓名、绑定子女与已确认记忆拼进陪伴系统提示，供 Realtime session.instructions 使用。

    child_name：已 active 绑定时传入（可为空串表示有绑定但无昵称）；未绑定传 None。
    """
    name = (user_name or "").strip()
    if name:
        profile_block = f"当前用户：姓名「{name}」（父母端）。"
    else:
        profile_block = "当前用户：姓名未知（父母端）；可用「您」称呼。"

    # 家庭绑定后注入子女称呼；关怀分享时用该称呼询问，未绑定则只陪伴不承诺通知
    if child_name is not None:
        bound = child_name.strip() or "家人"
        family_block = (
            f"已绑定子女：姓名「{bound}」。谈及家人或分享时用该称呼；"
            f"重要事情问清后，主动问要不要告诉「{bound}」，勿编造其他子女姓名。"
        )
    else:
        family_block = "尚未绑定子女；谈及具体子女姓名时勿编造；不可承诺已经通知家人。"

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

    return (
        f"{COCO_REALTIME_COMPANION_PROMPT}\n\n{profile_block}\n\n{family_block}\n\n{memory_block}"
    )


# 读图上下文上限，避免撑爆 Realtime instructions
_VISION_SCENE_MAX_CHARS = 1200

_SOURCE_LABELS = {
    "album": "相册照片",
    "camera": "眼前实拍",
    "screenshot": "手机截屏",
}


def build_vision_context_block(
    scene_description: str,
    *,
    source: str | None = None,
) -> str:
    """拼进 session.instructions 的照片块；换图时整块替换，不累加。"""
    scene = (scene_description or "").strip()
    if len(scene) > _VISION_SCENE_MAX_CHARS:
        scene = scene[:_VISION_SCENE_MAX_CHARS] + "…"
    if not scene:
        scene = "（读图结果为空，请诚实说看不太清。）"

    source_key = (source or "").strip().lower()
    source_label = _SOURCE_LABELS.get(source_key, "一张照片")

    return f"""
【当前照片上下文】（系统读图结果，不是用户原话；换图时整块替换）
来源：{source_label}
读图内容：
{scene}

关于这张照片：
1. 用户刚把这张图交给你看。请先用一两句口语说明你看到了什么，再自然等对方追问。
2. 只依据上述读图内容，图上没有的不要编造。
3. 药盒文字、账单、验证码、一次性通知等不要记入长期记忆。
4. 不做医疗诊断或剂量建议；不把未知链接判为绝对安全。
5. 若照片涉及受伤、就医或身体不适，按关怀对话规则先陪伴追问，不要立刻分享。
""".strip()


def merge_instructions_with_vision(
    base_instructions: str,
    scene_description: str,
    *,
    source: str | None = None,
) -> str:
    """在陪伴基线 instructions 上附加（或替换）照片块。"""
    base = (base_instructions or "").strip()
    vision_block = build_vision_context_block(scene_description, source=source)
    if not base:
        return vision_block
    return f"{base}\n\n{vision_block}"


# 触发可可开口：不作为用户字幕转发（桥接侧会抑制 user.final）
VISION_INJECT_TRIGGER_TEXT = (
    "（系统：用户刚把一张照片交给你看。请根据当前照片上下文，"
    "用一两句口语说说你看到了什么，然后等用户继续说。）"
)
