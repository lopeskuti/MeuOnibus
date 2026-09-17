#!/usr/bin/env python3
"""Gera a base estática de estações de metrô e trem a partir do OpenStreetMap."""

from __future__ import annotations

import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "assets" / "rail" / "rail_network.json"
BBOX = "(-24.15,-47.25,-23.05,-46.00)"
ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
)

LINES = (
    ("L1", "Linha 1-Azul", "metro", "0xff0B4EA2", r"linha\\s*0?1(\\D|$)"),
    ("L2", "Linha 2-Verde", "metro", "0xff008C5A", r"linha\\s*0?2(\\D|$)"),
    ("L3", "Linha 3-Vermelha", "metro", "0xffE4373A", r"linha\\s*0?3(\\D|$)"),
    ("L4", "Linha 4-Amarela", "metro", "0xffF5C518", r"linha\\s*0?4(\\D|$)"),
    ("L5", "Linha 5-Lilás", "metro", "0xff8E4C9E", r"linha\\s*0?5(\\D|$)"),
    ("L15", "Linha 15-Prata", "metro", "0xff7E858B", r"linha\\s*15(\\D|$)"),
    ("L7", "Linha 7-Rubi", "trem", "0xffA6455D", r"linha\\s*0?7(\\D|$)"),
    ("L8", "Linha 8-Diamante", "trem", "0xff9CA6AE", r"linha\\s*0?8(\\D|$)"),
    ("L9", "Linha 9-Esmeralda", "trem", "0xff00A98F", r"linha\\s*0?9(\\D|$)"),
    ("L10", "Linha 10-Turquesa", "trem", "0xff12A5B5", r"linha\\s*10(\\D|$)"),
    ("L11", "Linha 11-Coral", "trem", "0xffF26649", r"linha\\s*11(\\D|$)"),
    ("L12", "Linha 12-Safira", "trem", "0xff1B3F92", r"linha\\s*12(\\D|$)"),
    ("L13", "Linha 13-Jade", "trem", "0xff3EA75B", r"linha\\s*13(\\D|$)"),
)


def norm(value: str) -> str:
    value = unicodedata.normalize("NFD", value.upper())
    value = "".join(char for char in value if unicodedata.category(char) != "Mn")
    return re.sub(r"[^A-Z0-9]+", " ", value).strip()


def fetch() -> dict:
    query = f"""[out:json][timeout:180];
relation[route~"^(subway|train|monorail|light_rail)$"]{BBOX};
out body;
>;
out body;"""
    body = urllib.parse.urlencode({"data": query}).encode()
    headers = {"User-Agent": "MeuOnibus/1.0 (https://github.com/lopeskuti/MeuOnibus)"}
    last_error: Exception | None = None
    for endpoint in ENDPOINTS:
        try:
            request = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
            with urllib.request.urlopen(request, timeout=240) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            last_error = error
            time.sleep(3)
    raise SystemExit(f"Não foi possível consultar OpenStreetMap/Overpass: {last_error}")


def main() -> None:
    elements = fetch().get("elements", [])
    relations = [item for item in elements if item.get("type") == "relation"]
    nodes = {item["id"]: item for item in elements if item.get("type") == "node" and item.get("tags", {}).get("name")}

    stations: dict[str, dict] = {}
    line_output = []
    for line_id, title, mode, color, pattern in LINES:
        matching = [
            relation for relation in relations
            if re.search(pattern, norm(relation.get("tags", {}).get("name", "")))
        ]
        member_nodes = []
        for relation in matching:
            member_nodes.extend(
                member["ref"] for member in relation.get("members", [])
                if member.get("type") == "node" and member.get("ref") in nodes
            )

        seen = set()
        for node_id in member_nodes:
            node = nodes[node_id]
            tags = node.get("tags", {})
            name = tags.get("name", "").strip()
            if not name or node_id in seen:
                continue
            seen.add(node_id)
            key = norm(name)
            station = stations.setdefault(key, {
                "id": f"osm-{node_id}",
                "name": name,
                "lat": node["lat"],
                "lon": node["lon"],
                "lineIds": [],
            })
            if line_id not in station["lineIds"]:
                station["lineIds"].append(line_id)

        line_output.append({"id": line_id, "name": title, "mode": mode, "color": color})

    result = {
        "source": "OpenStreetMap contributors",
        "updatedAt": datetime.now(UTC).isoformat(),
        "lines": line_output,
        "stations": sorted(stations.values(), key=lambda station: station["name"]),
    }
    if not result["stations"]:
        raise SystemExit("A consulta não retornou estações ferroviárias utilizáveis.")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"OK: {len(result['stations'])} estações ferroviárias geradas.")


if __name__ == "__main__":
    main()
