"""用量费用估算：按百炼官网单价实时计算。"""

from __future__ import annotations

from decimal import Decimal

from coco_admin.usage.pricing import (
    attach_cost_estimates,
    estimate_token_cost_cny,
    resolve_model_pricing,
)


def test_resolve_model_pricing_prefix_match() -> None:
    pricing = resolve_model_pricing("qwen-plus-2025-12-01")
    assert pricing is not None
    assert pricing.input_per_million == Decimal("0.8")
    assert pricing.output_per_million == Decimal("2")


def test_estimate_token_cost_cny() -> None:
    # qwen-plus：0.8/百万输入 + 2/百万输出
    cost, pricing = estimate_token_cost_cny("qwen-plus", 1_000_000, 500_000)
    assert pricing is not None
    assert cost == Decimal("1.8")


def test_attach_cost_estimates_summary_and_ranking() -> None:
    stats = {
        "summary": {"total_tokens": 180},
        "by_model": [
            {
                "model": "qwen-plus",
                "input_tokens": 100,
                "output_tokens": 20,
                "total_tokens": 120,
                "call_count": 1,
            },
            {
                "model": "qwen-audio-3.0-realtime-plus",
                "input_tokens": 50,
                "output_tokens": 10,
                "total_tokens": 60,
                "call_count": 1,
            },
        ],
        "ranking": [
            {"user_id": "u1", "total_tokens": 180},
            {"user_id": "u2", "total_tokens": 12},
        ],
    }
    user_model_usage = [
        {"user_id": "u1", "model": "qwen-plus", "input_tokens": 100, "output_tokens": 20},
        {
            "user_id": "u1",
            "model": "qwen-audio-3.0-realtime-plus",
            "input_tokens": 50,
            "output_tokens": 10,
        },
        {"user_id": "u2", "model": "qwen-plus", "input_tokens": 10, "output_tokens": 2},
    ]

    enriched = attach_cost_estimates(stats, user_model_usage=user_model_usage)

    assert enriched["summary"]["estimated_cost_label"].startswith("¥")
    assert enriched["by_model"][0]["estimated_cost_cny"] is not None
    assert enriched["ranking"][0]["estimated_cost_label"].startswith("¥")
    assert enriched["ranking"][1]["estimated_cost_label"].startswith("¥")
    assert enriched["cost_meta"]["pricing_doc_url"].startswith("https://")
