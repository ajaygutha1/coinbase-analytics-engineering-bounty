#!/usr/bin/env python3
"""Render the dbt DAG from target/manifest.json as a Mermaid diagram in docs/LINEAGE.md.

GitHub renders Mermaid natively, so the lineage in the README is generated from the real
manifest instead of drawn by hand and left to drift. Run after `dbt docs generate` (or any
`dbt build`, which also writes the manifest).
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "target" / "manifest.json"
OUT = ROOT / "docs" / "LINEAGE.md"

LAYER_STYLE = {
    "seed": ("seeds", "fill:#f3f4f6,stroke:#6b7280,color:#111"),
    "staging": ("staging", "fill:#e0f2fe,stroke:#0284c7,color:#111"),
    "intermediate": ("intermediate", "fill:#fef3c7,stroke:#d97706,color:#111"),
    "marts": ("marts", "fill:#dcfce7,stroke:#16a34a,color:#111"),
    "weekly": ("weekly", "fill:#ede9fe,stroke:#7c3aed,color:#111"),
    "utilities": ("utilities", "fill:#f3f4f6,stroke:#6b7280,color:#111"),
    "exposure": ("exposures", "fill:#fee2e2,stroke:#dc2626,color:#111"),
}


def layer_of(node: dict) -> str:
    if node["resource_type"] == "seed":
        return "seed"
    if node["resource_type"] == "exposure":
        return "exposure"
    parts = node.get("path", "").split("/")
    return parts[0] if parts and parts[0] in LAYER_STYLE else "marts"


def label_of(node: dict) -> str:
    name = node["name"]
    if node.get("version") is not None:
        name = f"{name} v{node['version']}"
    return name


def main() -> None:
    m = json.loads(MANIFEST.read_text())
    nodes = {k: v for k, v in m["nodes"].items() if v["resource_type"] in ("model", "seed")}
    nodes.update(m.get("exposures", {}))
    ids = {k: f"n{i}" for i, k in enumerate(sorted(nodes))}

    lines = ["```mermaid", "flowchart LR"]
    by_layer: dict[str, list[str]] = {}
    for k in sorted(nodes):
        by_layer.setdefault(layer_of(nodes[k]), []).append(k)
    for layer in LAYER_STYLE:
        members = by_layer.get(layer)
        if not members:
            continue
        title, _ = LAYER_STYLE[layer]
        lines.append(f"  subgraph {title}")
        lines.append("    direction TB")
        for k in sorted(members, key=lambda x: nodes[x]["name"]):
            shape = ("[(", ")]") if layer == "seed" else ("([", "])") if layer == "exposure" else ("[", "]")
            lines.append(f"    {ids[k]}{shape[0]}\"{label_of(nodes[k])}\"{shape[1]}")
        lines.append("  end")
    # Everything below is sorted so the output is byte-identical on every machine; CI diffs it.
    edges = sorted(
        (ids[dep], ids[k])
        for k, v in nodes.items()
        for dep in v.get("depends_on", {}).get("nodes", [])
        if dep in ids
    )
    lines.extend(f"  {src} --> {dst}" for src, dst in edges)
    for layer, (_, style) in LAYER_STYLE.items():
        for k in sorted(by_layer.get(layer, []), key=lambda x: nodes[x]["name"]):
            lines.append(f"  style {ids[k]} {style}")
    lines.append("```")

    OUT.write_text(
        "# Lineage\n\nGenerated from `target/manifest.json` by `scripts/render_lineage.py`. "
        "Seeds are cylinders, models are boxes, the exposure is a pill. Tests are omitted for legibility; "
        "`dbt ls --select +exposure:growth_onboarding_review_deck` lists everything the deck depends on.\n\n"
        + "\n".join(lines) + "\n"
    )
    print(f"wrote {OUT.relative_to(ROOT)} with {len(nodes)} nodes")


if __name__ == "__main__":
    main()
