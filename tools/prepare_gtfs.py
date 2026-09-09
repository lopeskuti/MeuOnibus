#!/usr/bin/env python3
from __future__ import annotations
import csv, io, json, sys, zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'gtfs'

def rows(z: zipfile.ZipFile, name: str):
    with z.open(name) as raw:
        text = io.TextIOWrapper(raw, encoding='utf-8-sig', newline='')
        yield from csv.DictReader(text)

def main(path: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        required = {'stops.txt','routes.txt','trips.txt','stop_times.txt','shapes.txt'}
        missing = required - names
        if missing:
            raise SystemExit(f'GTFS sem arquivos obrigatórios: {sorted(missing)}')

        stops = []
        for r in rows(z, 'stops.txt'):
            try:
                lat, lon = float(r['stop_lat']), float(r['stop_lon'])
            except (ValueError, KeyError):
                continue
            stops.append({'id': r['stop_id'], 'name': r.get('stop_name') or 'Ponto', 'lat': lat, 'lon': lon})

        base_routes = {}
        for r in rows(z, 'routes.txt'):
            base_routes[r['route_id']] = {'shortName': r.get('route_short_name') or r['route_id'], 'longName': r.get('route_long_name') or ''}

        variant_by_trip = {}
        variants = {}
        for r in rows(z, 'trips.txt'):
            route_id = r['route_id']
            direction = r.get('direction_id') or '0'
            variant_id = f'{route_id}:{direction}'
            variant_by_trip[r['trip_id']] = variant_id
            if variant_id not in variants:
                b = base_routes.get(route_id, {'shortName': route_id, 'longName': ''})
                variants[variant_id] = {'shortName': b['shortName'], 'longName': r.get('trip_headsign') or b['longName'], 'shapeId': r.get('shape_id') or None}

        stop_routes = defaultdict(set)
        for r in rows(z, 'stop_times.txt'):
            vid = variant_by_trip.get(r['trip_id'])
            if vid:
                stop_routes[r['stop_id']].add(vid)

        used_shapes = {v['shapeId'] for v in variants.values() if v.get('shapeId')}
        shapes = defaultdict(list)
        for r in rows(z, 'shapes.txt'):
            sid = r['shape_id']
            if sid not in used_shapes:
                continue
            try:
                seq = int(r['shape_pt_sequence']); lat = float(r['shape_pt_lat']); lon = float(r['shape_pt_lon'])
            except (ValueError, KeyError):
                continue
            shapes[sid].append((seq, lat, lon))
        compact_shapes = {sid: [[lat, lon] for _, lat, lon in sorted(points)] for sid, points in shapes.items()}

    (OUT/'stops.json').write_text(json.dumps(stops, ensure_ascii=False, separators=(',',':')), encoding='utf-8')
    (OUT/'routes.json').write_text(json.dumps(variants, ensure_ascii=False, separators=(',',':')), encoding='utf-8')
    (OUT/'stop_routes.json').write_text(json.dumps({k: sorted(v) for k,v in stop_routes.items()}, ensure_ascii=False, separators=(',',':')), encoding='utf-8')
    (OUT/'shapes.json').write_text(json.dumps(compact_shapes, ensure_ascii=False, separators=(',',':')), encoding='utf-8')
    print(f'OK: {len(stops)} pontos, {len(variants)} variantes, {len(compact_shapes)} shapes')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Uso: python3 tools/prepare_gtfs.py /caminho/gtfs.zip')
    main(sys.argv[1])
