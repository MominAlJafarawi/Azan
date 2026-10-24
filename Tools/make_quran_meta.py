#!/usr/bin/env python3
"""Turns Tanzil's quran-data.js (CC BY 3.0, tanzil.net) into Resources/Quran/quran-meta.json.
Usage: python3 -I Tools/make_quran_meta.py path/to/quran-data.js Resources/Quran/quran-meta.json"""
import json, re, sys

src = open(sys.argv[1], encoding='utf-8').read()

def block(name):
    m = re.search(r'QuranData\.' + name + r'\s*=\s*\[(.*?)\n\];', src, re.S)
    body = re.sub(r'//[^\n]*', '', m.group(1))
    rows = re.findall(r'\[([^\[\]]*)\]', body)
    out = []
    for r in rows:
        if not r.strip():
            continue
        out.append([int(x) if re.fullmatch(r'\s*-?\d+\s*', x) else x.strip().strip("'") for x in r.split(',')])
    return out

suras = [[r[4], r[1], r[7], r[0]] for r in block('Sura')[:114]]  # name, ayas, type, start index
meta = {
    'license': 'Quran metadata (c) Tanzil Project, Creative Commons Attribution 3.0, https://tanzil.net',
    'suras': suras,
    'pages': [r[:2] for r in block('Page')[:604]],
    'juz': [r[:2] for r in block('Juz')[:30]],
    'sajda': [r[:2] for r in block('Sajda')],
}
assert len(meta['suras']) == 114 and len(meta['pages']) == 604 and len(meta['juz']) == 30, {k: len(v) for k, v in meta.items()}
assert sum(s[1] for s in suras) == 6236
json.dump(meta, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print('ok', {k: len(v) for k, v in meta.items() if k != 'license'})
