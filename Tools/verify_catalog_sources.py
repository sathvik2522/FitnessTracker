#!/usr/bin/env python3
"""Independently check bundled values against downloaded source rows (no network)."""
import argparse, csv, io, json, zipfile
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);args=p.parse_args()
root=Path(__file__).resolve().parent.parent/'PersonalFitness/Resources/Catalogs'
foods=json.loads((root/'foods-v1.json').read_text())['foods']
exercises=json.loads((root/'exercises-v1.json').read_text())['exercises']
z=zipfile.ZipFile(args.sources/'usda-sr-legacy.zip')
def rows(name): return csv.DictReader(io.TextIOWrapper(z.open(next(x for x in z.namelist() if x.endswith('/'+name+'.csv'))),encoding='utf-8-sig'))
names={r['fdc_id']:r for r in rows('food')}
values={(r['fdc_id'],r['nutrient_id']):r['amount'] for r in rows('food_nutrient') if r['nutrient_id'] in ['1008','1003','1005','1004']}
for record in foods:
    fid=record['recordID'];definition=record['definition']
    assert names[fid]['data_type']=='sr_legacy_food'
    assert definition['name']==names[fid]['description']
    assert definition['referenceQuantity']==100 and definition['referenceUnit']=='g'
    for key,nid in [('calories','1008'),('protein','1003'),('carbohydrates','1005'),('fat','1004')]:
        assert definition['nutrients'][key]==float(values[(fid,nid)]), (fid,key)
source={r['id']:r for r in json.loads((args.sources/'exercises.json').read_text())}
omitted_blank_steps=0
for record in exercises:
    original=source[record['recordID']];actual=record['exercise']
    assert actual['name']==original['name']
    assert actual['equipment']==original.get('equipment')
    assert actual['primaryMuscles']==original['primaryMuscles']
    assert actual['secondaryMuscles']==original['secondaryMuscles']
    assert actual['instructions']==[t for t in original['instructions'] if t.strip()]
    omitted_blank_steps+=sum(not t.strip() for t in original['instructions'])
    assert 'images' not in actual
print(json.dumps(dict(verifiedFoodRecords=len(foods),verifiedExerciseRecords=len(exercises),omittedBlankInstructionSteps=omitted_blank_steps,foodMacroSourceEquality=True,exerciseTextSourceEquality=True),indent=2))
