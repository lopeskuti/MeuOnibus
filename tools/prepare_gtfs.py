#!/usr/bin/env python3
from __future__ import annotations

import csv
import io
import json
import math
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'gtfs'
SHAPE_SIMPLIFY_METERS = 8.0
COORD_DECIMALS = 5


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
        for r in rows(z, 'stops.txt'):
            try:
                lat, lon = float(r['stop_lat']), float(r['stop_lon'])
            except (ValueError, KeyError):
                continue
            stops.append({
                'id': r['stop_id'],
                'name': r.get('stop_name') or 'Ponto',
                'lat': round(lat, 6),
                'lon': round(lon, 6),
            })

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
    (OUT / 'shapes.json').write_text(
        json.dumps(compact_shapes, ensure_ascii=False, separators=(',', ':')), encoding='utf-8'
    )

    shape_points = sum(len(points) for points in compact_shapes.values())
    print(
        f'OK: {len(stops)} pontos, {len(variants)} variantes, '
        f'{len(compact_shapes)} shapes, {shape_points} pontos de shape simplificados'
    )


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Uso: python3 tools/prepare_gtfs.py /caminho/gtfs.zip')
    main(sys.argv[1])
