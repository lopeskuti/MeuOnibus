#!/usr/bin/env python3
from __future__ import annotations

import csv
import io
import json
import math
import re
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'gtfs'
SHAPE_SIMPLIFY_METERS = 8.0
COORD_DECIMALS = 5
TERMINAL_PATTERN = re.compile(r'\b(?:terminal|term\.)\s+(.+?)(?=\s*(?:[-–—]\s*)?(?:plataforma|plat\.)\b|\s+ref\.:|$)', re.IGNORECASE)
PLATFORM_PATTERN = re.compile(r'\b(?:plataforma|plat\.)\s*([a-z0-9]+)\b', re.IGNORECASE)
SIDE_PATTERN = re.compile(r'\(lado\s+([^)]+)\)', re.IGNORECASE)


def _terminal_metadata(row: dict[str, str]) -> tuple[str, str] | None:
    for value in (row.get('stop_name') or '', row.get('stop_desc') or ''):
        match = TERMINAL_PATTERN.search(value)
        if not match:
            continue
        raw_name = ' '.join(match.group(1).split())
        side_match = SIDE_PATTERN.search(raw_name)
        terminal_name = SIDE_PATTERN.sub('', raw_name).strip(' -–—')
        if not terminal_name:
            continue
        platform_match = PLATFORM_PATTERN.search(value)
        platform_name = f'Plataforma {platform_match.group(1).upper()}' if platform_match else 'Ponto do terminal'
        if side_match:
            platform_name = f'Lado {side_match.group(1).strip().title()} • {platform_name}'
        return f'Terminal {terminal_name}', platform_name
    return None


def _terminal_id(name: str) -> str:
    normalised = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
    return f'terminal-{normalised}'


def build_terminals(stops: list[dict], source_rows: dict[str, dict[str, str]]) -> list[dict]:
    grouped: dict[str, dict] = {}
    for stop in stops:
        metadata = _terminal_metadata(source_rows[stop['id']])
        if metadata is None:
            continue
        terminal_name, platform_name = metadata
        terminal_id = _terminal_id(terminal_name)
        terminal = grouped.setdefault(terminal_id, {'id': terminal_id, 'name': terminal_name, 'stops': [], 'platforms': defaultdict(list)})
        terminal['stops'].append(stop)
        terminal['platforms'][platform_name].append(stop['id'])
    result = []
    for terminal in grouped.values():
        terminal_stops = terminal['stops']
        result.append({
            'id': terminal['id'],
            'name': terminal['name'],
            'lat': round(sum(stop['lat'] for stop in terminal_stops) / len(terminal_stops), 6),
            'lon': round(sum(stop['lon'] for stop in terminal_stops) / len(terminal_stops), 6),
            'platforms': [{'name': name, 'stopIds': sorted(ids)} for name, ids in sorted(terminal['platforms'].items())],
        })
    return sorted(result, key=lambda terminal: terminal['name'])


def rows(z: zipfile.ZipFile, name: str):
    with z.open(name) as raw:
        text = io.TextIOWrapper(raw, encoding='utf-8-sig', newline='')
        yield from csv.DictReader(text)


def simplify_shape(points: list[tuple[int, float, float]], epsilon_m: float) -> list[list[float]]:
    ordered = [(lat, lon) for _, lat, lon in sorted(points)]
    if len(ordered) <= 2:
        return [[round(lat, COORD_DECIMALS), round(lon, COORD_DECIMALS)] for lat, lon in ordered]

    lat0 = sum(lat for lat, _ in ordered) / len(ordered)
    sx = 111320.0 * math.cos(math.radians(lat0))
    sy = 110540.0
    xy = [(lon * sx, lat * sy) for lat, lon in ordered]

    keep = {0, len(ordered) - 1}
    stack = [(0, len(ordered) - 1)]
    epsilon2 = epsilon_m * epsilon_m

    while stack:
        start, end = stack.pop()
        ax, ay = xy[start]
        bx, by = xy[end]
        dx, dy = bx - ax, by - ay
        denominator = dx * dx + dy * dy
        farthest_index = -1
        farthest_distance2 = -1.0

        for index in range(start + 1, end):
            px, py = xy[index]
            if denominator:
                t = ((px - ax) * dx + (py - ay) * dy) / denominator
                t = max(0.0, min(1.0, t))
                qx, qy = ax + t * dx, ay + t * dy
            else:
                qx, qy = ax, ay

            distance2 = (px - qx) ** 2 + (py - qy) ** 2
            if distance2 > farthest_distance2:
                farthest_distance2 = distance2
                farthest_index = index

        if farthest_distance2 > epsilon2:
            keep.add(farthest_index)
            stack.append((start, farthest_index))
            stack.append((farthest_index, end))

    return [
        [round(ordered[index][0], COORD_DECIMALS), round(ordered[index][1], COORD_DECIMALS)]
        for index in sorted(keep)
    ]


def main(path: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        required = {'stops.txt', 'routes.txt', 'trips.txt', 'stop_times.txt', 'shapes.txt'}
        missing = required - names
        if missing:
            raise SystemExit(f'GTFS sem arquivos obrigatórios: {sorted(missing)}')

        stops = []
        stop_source_rows = {}
        for r in rows(z, 'stops.txt'):
            try:
                lat, lon = float(r['stop_lat']), float(r['stop_lon'])
            except (ValueError, KeyError):
                continue
            stop = {'id': r['stop_id'], 'name': r.get('stop_name') or 'Ponto', 'lat': round(lat, 6), 'lon': round(lon, 6)}
            stops.append(stop)
            stop_source_rows[stop['id']] = r

        base_routes = {}
        for r in rows(z, 'routes.txt'):
            base_routes[r['route_id']] = {
                'shortName': r.get('route_short_name') or r['route_id'],
                'longName': r.get('route_long_name') or '',
            }

        variant_by_trip = {}
        variants = {}
        for r in rows(z, 'trips.txt'):
            route_id = r['route_id']
            direction = r.get('direction_id') or '0'
            variant_id = f'{route_id}:{direction}'
            variant_by_trip[r['trip_id']] = variant_id
            if variant_id not in variants:
                base = base_routes.get(route_id, {'shortName': route_id, 'longName': ''})
                variants[variant_id] = {
                    'shortName': base['shortName'],
                    'longName': r.get('trip_headsign') or base['longName'],
                    'shapeId': r.get('shape_id') or None,
                }

        stop_routes = defaultdict(set)
        for r in rows(z, 'stop_times.txt'):
            variant_id = variant_by_trip.get(r['trip_id'])
            if variant_id:
                stop_routes[r['stop_id']].add(variant_id)

        used_shapes = {v['shapeId'] for v in variants.values() if v.get('shapeId')}
        shapes = defaultdict(list)
        for r in rows(z, 'shapes.txt'):
            shape_id = r['shape_id']
            if shape_id not in used_shapes:
                continue
            try:
                sequence = int(r['shape_pt_sequence'])
                lat = float(r['shape_pt_lat'])
                lon = float(r['shape_pt_lon'])
            except (ValueError, KeyError):
                continue
            shapes[shape_id].append((sequence, lat, lon))

        compact_shapes = {
            shape_id: simplify_shape(points, SHAPE_SIMPLIFY_METERS)
            for shape_id, points in shapes.items()
        }
        terminals = build_terminals(stops, stop_source_rows)

    (OUT / 'stops.json').write_text(
        json.dumps(stops, ensure_ascii=False, separators=(',', ':')), encoding='utf-8'
    )
    (OUT / 'routes.json').write_text(
        json.dumps(variants, ensure_ascii=False, separators=(',', ':')), encoding='utf-8'
    )
    (OUT / 'stop_routes.json').write_text(
        json.dumps({k: sorted(v) for k, v in stop_routes.items()}, ensure_ascii=False, separators=(',', ':')),
        encoding='utf-8',
    )
    (OUT / 'terminals.json').write_text(json.dumps(terminals, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    (OUT / 'shapes.json').write_text(
        json.dumps(compact_shapes, ensure_ascii=False, separators=(',', ':')), encoding='utf-8'
    )

    shape_points = sum(len(points) for points in compact_shapes.values())
    print(
        f'OK: {len(stops)} pontos, {len(terminals)} terminais, {len(variants)} variantes, '
        f'{len(compact_shapes)} shapes, {shape_points} pontos de shape simplificados'
    )


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Uso: python3 tools/prepare_gtfs.py /caminho/gtfs.zip')
    main(sys.argv[1])
