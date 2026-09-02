"""百炼官网单价（华北2），仅用于运营页实时估算，不落库。"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Any

# 价格来源：阿里云百炼模型价格页（华北2 第一档）
PRICING_DOC_URL = "https://help.aliyun.com/zh/model-studio/model-pricing"
PRICING_REGION_LABEL = "华北2（北京）"
MILLION = Decimal(1_000_000)


@dataclass(frozen=True, slots=True)
class TokenPricing:
    """按百万 Token 计价（元）。"""

    input_per_million: Decimal
    output_per_million: Decimal
    note: str | None = None


# 前缀越长越优先，便于 qwen-plus-2025-12-01 等快照模型复用同价
MODEL_PRICING_RULES: tuple[tuple[str, TokenPricing], ...] = (
    (
        "qwen-audio-3.0-realtime-plus",
        TokenPricing(
            Decimal("5"),
            Decimal("40"),
            note="Realtime 含音频 Token 时实际费用可能更高（音频输出 150 元/百万）",
        ),
    ),
    (
        "qwen-audio-3.0-realtime-flash",
        TokenPricing(
            Decimal("3"),
            Decimal("30"),
            note="Realtime 含音频 Token 时实际费用可能更高（音频输出 100 元/百万）",
        ),
    ),
    ("qwen3.7-plus", TokenPricing(Decimal("2"), Decimal("8"))),
    ("qwen3.6-plus", TokenPricing(Decimal("2"), Decimal("12"))),
    ("qwen-plus", TokenPricing(Decimal("0.8"), Decimal("2"))),
    ("qwen-max", TokenPricing(Decimal("2.4"), Decimal("9.6"))),
    ("text-embedding", TokenPricing(Decimal("0.7"), Decimal("0"))),
)


def resolve_model_pricing(model: str) -> TokenPricing | None:
    """按 model id 前缀匹配官网单价。"""
    normalized = model.strip().lower()
    if not normalized:
        return None
    for prefix, pricing in MODEL_PRICING_RULES:
        if normalized == prefix or normalized.startswith(f"{prefix}-"):
            return pricing
    return None


def estimate_token_cost_cny(
    model: str,
    input_tokens: int,
    output_tokens: int,
) -> tuple[Decimal | None, TokenPricing | None]:
    """根据 input/output Token 估算单次聚合费用（元）。"""
    pricing = resolve_model_pricing(model)
    if pricing is None:
        return None, None
    cost = (
        Decimal(input_tokens) * pricing.input_per_million
        + Decimal(output_tokens) * pricing.output_per_million
    ) / MILLION
    return cost, pricing


def _quantize_cny(amount: Decimal) -> Decimal:
    if amount >= Decimal("1"):
        return amount.quantize(Decimal("0.01"))
    if amount >= Decimal("0.01"):
        return amount.quantize(Decimal("0.0001"))
    return amount.quantize(Decimal("0.000001"))


def format_cny(amount: Decimal | None) -> str:
    if amount is None:
        return "—"
    quantized = _quantize_cny(amount)
    return f"¥{quantized:f}"


def attach_cost_estimates(
    stats: dict[str, Any],
    *,
    user_model_usage: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """在内存中为 stats 附加估算费用字段，不写数据库。"""
    total_cost = Decimal("0")
    has_priced_model = False
    unknown_models: set[str] = set()

    enriched_by_model: list[dict[str, Any]] = []
    for row in stats.get("by_model", []):
        model = str(row.get("model", ""))
        input_tokens = int(row.get("input_tokens") or 0)
        output_tokens = int(row.get("output_tokens") or 0)
        cost, pricing = estimate_token_cost_cny(model, input_tokens, output_tokens)
        enriched = dict(row)
        enriched["estimated_cost_cny"] = float(cost) if cost is not None else None
        enriched["estimated_cost_label"] = format_cny(cost)
        enriched["pricing_note"] = pricing.note if pricing else None
        enriched["pricing_known"] = pricing is not None
        enriched_by_model.append(enriched)
        if cost is not None:
            has_priced_model = True
            total_cost += cost
        elif model:
            unknown_models.add(model)

    user_costs: dict[str, Decimal] = {}
    if user_model_usage:
        for row in user_model_usage:
            user_id = str(row["user_id"])
            cost, _ = estimate_token_cost_cny(
                str(row["model"]),
                int(row["input_tokens"]),
                int(row["output_tokens"]),
            )
            if cost is None:
                continue
            user_costs[user_id] = user_costs.get(user_id, Decimal("0")) + cost

    enriched_ranking: list[dict[str, Any]] = []
    for row in stats.get("ranking", []):
        enriched = dict(row)
        user_cost = user_costs.get(str(row["user_id"]))
        enriched["estimated_cost_cny"] = float(user_cost) if user_cost is not None else None
        enriched["estimated_cost_label"] = format_cny(user_cost)
        enriched_ranking.append(enriched)

    summary = dict(stats.get("summary", {}))
    summary["estimated_cost_cny"] = float(total_cost) if has_priced_model else None
    summary["estimated_cost_label"] = format_cny(total_cost if has_priced_model else None)
    summary["unknown_pricing_models"] = sorted(unknown_models)

    enriched = dict(stats)
    enriched["summary"] = summary
    enriched["by_model"] = enriched_by_model
    enriched["ranking"] = enriched_ranking
    enriched["cost_meta"] = {
        "pricing_doc_url": PRICING_DOC_URL,
        "pricing_region": PRICING_REGION_LABEL,
        "disclaimer": (
            "按百炼官网 Token 单价实时估算，不含免费额度抵扣、阶梯价与限时折扣；"
            "Realtime 未区分文本/音频 Token 时可能偏低。"
        ),
    }
    return enriched
