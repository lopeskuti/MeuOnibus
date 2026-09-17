#!/usr/bin/env python3
"""Gera a base estática de estações de metrô e trem a partir do OpenStreetMap.

A associação privilegia a composição da rota; proximidade só é usada como contingência.
"""

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
    ("L1", "Linha 1-Azul", "metro", "0xff0B4EA2", r"linha\s*0?1(\D|$)"),
    ("L2", "Linha 2-Verde", "metro", "0xff008C5A", r"linha\s*0?2(\D|$)"),
    ("L3", "Linha 3-Vermelha", "metro", "0xffE4373A", r"linha\s*0?3(\D|$)"),
    ("L4", "Linha 4-Amarela", "metro", "0xffF5C518", r"linha\s*0?4(\D|$)"),
    ("L5", "Linha 5-Lilás", "metro", "0xff8E4C9E", r"linha\s*0?5(\D|$)"),
    ("L15", "Linha 15-Prata", "metro", "0xff7E858B", r"linha\s*15(\D|$)"),
    ("L7", "Linha 7-Rubi", "trem", "0xffA6455D", r"linha\s*0?7(\D|$)"),
    ("L8", "Linha 8-Diamante", "trem", "0xff9CA6AE", r"linha\s*0?8(\D|$)"),
    ("L9", "Linha 9-Esmeralda", "trem", "0xff00A98F", r"linha\s*0?9(\D|$)"),
    ("L10", "Linha 10-Turquesa", "trem", "0xff12A5B5", r"linha\s*10(\D|$)"),
    ("L11", "Linha 11-Coral", "trem", "0xffF26649", r"linha\s*11(\D|$)"),
    ("L12", "Linha 12-Safira", "trem", "0xff1B3F92", r"linha\s*12(\D|$)"),
    ("L13", "Linha 13-Jade", "trem", "0xff3EA75B", r"linha\s*13(\D|$)"),
)


def norm(value: str) -> str:
    value = unicodedata.normalize("NFD", value.upper())
    value = "".join(char for char in value if unicodedata.category(char) != "Mn")
    return re.sub(r"[^A-Z0-9]+", " ", value).strip()


def query(query: str) -> dict:
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


def distance_to_route_meters(lat: float, lon: float, points: list[tuple[float, float]]) -> float:
    # Aproximação suficiente para associar a estação à geometria da linha.
    # O menor trecho entre estações metropolitanas é muito maior que o erro
    # introduzido por esta projeção local.
    lat_scale = 110_540.0
    lon_scale = 102_300.0
    return min(
        ((lat - point_lat) * lat_scale) ** 2 + ((lon - point_lon) * lon_scale) ** 2
        for point_lat, point_lon in points
    ) ** 0.5


def fetch_network() -> tuple[dict, dict]:
    routes = query(f"""[out:json][timeout:180];
relation[route~"^(subway|train|monorail|light_rail)$"]{BBOX};
out body;
>;
out body;""")
    stations = query(f"""[out:json][timeout:180];
(
  nwr["railway"~"^(station|halt)$"]["name"]{BBOX};
  nwr["station"~"^(subway|train)$"]["name"]{BBOX};
);
out center tags;""")
    return routes, stations

def main() -> None:
    route_data, station_data = fetch_network()
    route_elements = route_data.get("elements", [])
    nodes = {item["id"]: item for item in route_elements if item.get("type") == "node"}
    ways = {item["id"]: item for item in route_elements if item.get("type") == "way"}
    relations = [item for item in route_elements if item.get("type") == "relation"]

    line_points: dict[str, list[tuple[float, float]]] = {}
    line_station_names: dict[str, set[str]] = {}
    for line_id, _, _, _, pattern in LINES:
        points: list[tuple[float, float]] = []
        station_names: set[str] = set()
        for relation in relations:
            tags = relation.get("tags", {})
            identity = norm(" ".join(str(tags.get(key, "")) for key in ("name", "ref", "from", "to")))
            network = norm(str(tags.get("network", "")))
            is_sp_rail = network in {
                "METRO DE SAO PAULO",
                "TREM METROPOLITANO DE SAO PAULO",
                "COMPANHIA PAULISTA DE TRENS METROPOLITANOS",
            }
            if not is_sp_rail or not re.search(pattern, identity, re.I):
                continue
            for member in relation.get("members", []):
                if member.get("type") == "node" and member.get("ref") in nodes:
                    node = nodes[member["ref"]]
                    points.append((node["lat"], node["lon"]))
                    if node.get("tags", {}).get("name"):
                        station_names.add(norm(node["tags"]["name"]))
                if member.get("type") == "way" and member.get("ref") in ways:
                    way = ways[member["ref"]]
                    if way.get("tags", {}).get("name"):
                        station_names.add(norm(way["tags"]["name"]))
                    for node_id in way.get("nodes", []):
                        node = nodes.get(node_id)
                        if node:
                            points.append((node["lat"], node["lon"]))
        if points:
            line_points[line_id] = points
            line_station_names[line_id] = station_names

    stations: dict[str, dict] = {}
    for item in station_data.get("elements", []):
        tags = item.get("tags", {})
        name = (tags.get("name") or "").strip()
        if not name:
            continue
        lat = item.get("lat") or item.get("center", {}).get("lat")
        lon = item.get("lon") or item.get("center", {}).get("lon")
        if lat is None or lon is None:
            continue
        station_name = norm(name)
        nearby_lines = [
            line_id for line_id, names in line_station_names.items()
            if station_name in names
        ]
        if not nearby_lines:
            nearby_lines = [
                line_id for line_id, points in line_points.items()
                if distance_to_route_meters(lat, lon, points) <= 350
            ]
        if not nearby_lines:
            continue
        key = norm(name)
        station = stations.setdefault(key, {
            "id": f"osm-{item['type']}-{item['id']}",
            "name": name,
            "lat": lat,
            "lon": lon,
            "lineIds": [],
        })
        station["lineIds"] = sorted(set(station["lineIds"]) | set(nearby_lines))

    line_output = [
        {"id": line_id, "name": title, "mode": mode, "color": color}
        for line_id, title, mode, color, _ in LINES
        if line_id in line_points
    ]
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