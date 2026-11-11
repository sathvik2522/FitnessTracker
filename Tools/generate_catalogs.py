#!/usr/bin/env python3
"""Build deterministic offline resources from verified, development-only bulk files.
No runtime networking. Source files live outside the app/repository by default.
"""
import argparse, csv, hashlib, io, json, math, re, shutil, uuid, zipfile
from pathlib import Path

NAMESPACE = uuid.UUID('655a7fd8-53dc-5b1e-95c1-dd6d769dce49')
COMMIT = 'f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5'
USDA_URL = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip'
EXERCISE_URL = f'https://raw.githubusercontent.com/yuhonas/free-exercise-db/{COMMIT}/dist/exercises.json'

def identity(source, record): return str(uuid.uuid5(NAMESPACE, source+'|'+record)).upper()
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def write(path, data): path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':'), sort_keys=True)+'\n')

def generate(sources, out):
    out.mkdir(parents=True, exist_ok=True)
    archive = sources/'usda-sr-legacy.zip'
    assert sha(archive) == 'b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0', 'USDA download changed: review source/release before regenerating'
    assert sha(sources/'exercises.json') == '5bb747e3fc658f095a60dcbf6d53c96627acdcc6ffb6fffde86f7e26995d40bf', 'Exercise download differs from pinned commit'
    assert sha(sources/'EXERCISE_LICENSE.md') == '6b0382b16279f26ff69014300541967a356a666eb0b91b422f6862f6b7dad17e', 'Exercise license differs from reviewed pinned text'
    z = zipfile.ZipFile(archive)
    def rows(name):
        key = next(x for x in z.namelist() if x.endswith('/'+name+'.csv'))
        return list(csv.DictReader(io.TextIOWrapper(z.open(key), encoding='utf-8-sig')))
    foods = rows('food')
    units = {r['id']:r['unit_name'].upper() for r in rows('nutrient')}
    assert all(units[k] == u for k,u in [('1008','KCAL'),('1003','G'),('1005','G'),('1004','G')])
    nutrients = {}
    for r in rows('food_nutrient'):
        if r['nutrient_id'] in ['1008', '1003', '1005', '1004']:
            nutrients.setdefault(r['fdc_id'], {})[r['nutrient_id']] = r
    portions = {}
    for r in rows('food_portion'):
        try:
            amount, grams = float(r['amount']), float(r['gram_weight'])
            if amount > 0 and grams > 0 and math.isfinite(grams):
                portions.setdefault(r['fdc_id'], []).append(dict(amount=amount, unitDescription=r['modifier'] or r['portion_description'] or 'source portion', gramWeight=grams))
        except ValueError: pass
    # Generic ingredient families, not branded/prepared restaurant meals. This
    # inclusion policy is explicit and inspectable; no nutrient values are authored.
    families = r'^(Spices,|Egg, (whole|white|yolk)|Chicken, broilers or fryers, breast, meat only|Rice, (white|brown|wild)|Mung beans,|Mungo beans,|Lentils,|Chickpeas |Chickpeas,|Pigeon peas |Pigeonpeas,|Beans, (kidney|black|pinto|small white)|Cowpeas,|Yogurt, (plain|Greek, plain)|Cheese, cottage, (creamed|nonfat|lowfat)|Milk, (whole|reduced fat|lowfat|nonfat)|Butter,|Butter oil,|Oil, (olive|coconut|sesame|peanut|sunflower|canola)|Sweet potato|Apples,|Grapes,|Watermelon,|Bananas,|Oranges,|Mangos,|Papayas,|Pineapple,|Strawberries,|Blueberries,|Avocados,|Peanuts,|Soybeans,|Nuts, (almonds|cashew nuts|walnuts|pistachio|coconut)|Seeds, (sesame|flaxseed|chia)|Oats|Wheat flour,|Wheat,|Millet,|Sorghum|Barley,|Quinoa,|Buckwheat,|Corn,|Peas, green,|Potatoes,|Tomatoes,|Onions,|Garlic,|Ginger root,|Spinach,|Kale,|Cabbage,|Cauliflower,|Broccoli,|Okra,|Eggplant,|Cucumber,|Carrots,|Beets,|Peppers,|Mushrooms,|Squash,|Pumpkin,|Coriander |Spearmint,|Peppermint,|Curry leaves|Tamarinds,|Dates,|Raisins,|Sugars, (brown|granulated)|Honey|Beverages, (Whey protein powder isolate|Protein powder whey based))'
    aliases = {'mung beans':['moong','green gram'], 'mungo beans':['urad','black gram'], 'lentils':['masoor dal'], 'chickpeas':['chana','garbanzo'], 'pigeon':['toor dal','arhar dal'], 'beans, kidney':['rajma'], 'cowpeas':['lobia'], 'yogurt, plain':['dahi','curd'], 'butter oil':['ghee'], 'coriander':['dhania','cilantro'], 'cumin':['jeera'], 'turmeric':['haldi'], 'cardamom':['elaichi'], 'fenugreek':['methi'], 'okra':['bhindi'], 'eggplant':['brinjal','baingan'], 'cauliflower':['gobi'], 'spinach':['palak'], 'millet':['bajra'], 'sorghum':['jowar'], 'wheat flour':['atta'], 'sweet potato':['shakarkandi'], 'watermelon':['tarbooz']}
    result, excluded = [], []
    for food in sorted(foods, key=lambda f: int(f['fdc_id'])):
        name, fid = food['description'], food['fdc_id']
        if not re.search(families, name, re.I): continue
        # Source SR Legacy also contains named commercial foods: omit those.
        if any(w in name.lower() for w in ['chobani','dannon','yoplait','campbell','kellogg','pillsbury','mcdonald','burger king','uncle ben','kamut']): continue
        ns = nutrients.get(fid, {})
        if set(ns) != {'1008','1003','1005','1004'} or any(not ns[n]['amount'] for n in ns):
            excluded.append(fid); continue
        values = [float(ns[n]['amount']) for n in ['1008','1003','1005','1004']]
        if not all(math.isfinite(v) and v >= 0 for v in values): excluded.append(fid); continue
        lower = name.lower()
        preparation = 'Raw' if re.search(r'\b(raw|uncooked)\b', lower) else 'Cooked' if re.search(r'\b(cooked|boiled|roasted|fried|baked|stewed|steamed|microwaved|grilled|sauteed|braised|scrambled|poached)\b', lower) else 'Not specified'
        als = sorted({a for term, words in aliases.items() if term in lower for a in words})
        # Bajra is pearl millet, not every millet; atta is whole wheat flour.
        if 'millet' in lower: als = [a for a in als if a != 'bajra']
        if 'wheat flour' in lower and 'whole' not in lower: als = [a for a in als if a != 'atta']
        ps = portions.get(fid, [])
        preferred = next((p for p in ps if p['unitDescription'] == 'serving'), ps[0] if ps else None)
        if preferred: ps = [preferred] + [p for p in ps if p != preferred]
        equivalents = ['serving', 100 / preferred['gramWeight']] if preferred else []
        definition = dict(name=name,preparation=preparation,nutrients=dict(zip(['calories','protein','carbohydrates','fat'],values)),referenceQuantity=100,referenceUnit='g',equivalents=equivalents,aliases=als,sourceServings=ps)
        # Swift dictionaries keyed by FoodUnit encode as alternating key/value arrays.
        evidence = '; '.join(n+':derivation='+ns[n]['derivation_id']+',n='+ (ns[n]['data_points'] or 'unreported') for n in ['1008','1003','1005','1004'])
        result.append(dict(id=identity('usda-sr-legacy',fid),recordID=fid,quality='Historical SR Legacy; per 100 g; '+evidence,definition=definition))
    source = dict(id='usda-sr-legacy',name='USDA FoodData Central — SR Legacy',url='https://fdc.nal.usda.gov/',license='CC0-1.0',licenseURL='https://fdc.nal.usda.gov/',attribution='U.S. Department of Agriculture, Agricultural Research Service. FoodData Central. SR Legacy, April 2018. Accessed October 18, 2026.',downloadURL=USDA_URL,sha256=sha(archive))
    write(out/'foods-v1.json',dict(schemaVersion=1,release='sr-2018-selection-1',source=source,foods=result,exercises=[]))
    exercises = json.loads((sources/'exercises.json').read_text())
    converted=[]
    for item in exercises:
        name=item['name']; lower=name.lower(); als=[]
        if 'fly' in lower or 'flies' in lower or 'flyes' in lower: als.append('chest fly' if 'reverse' not in lower and 'rear' not in lower else 'rear delt fly')
        if 'side lateral' in lower: als.append('lateral raise')
        if item['id']=='Split_Squat_with_Dumbbells': als.append('Bulgarian split squat') # source instructions elevate the rear foot
        if 'pullup' in lower or 'pull-up' in lower or 'pull up' in lower: als.extend(['pull up','pull-up'])
        eq=item.get('equipment'); primary=item.get('primaryMuscles',[])
        snap=dict(id=identity('free-exercise-db',item['id']),name=name,notes='',category=item['category'],muscleGroup=', '.join(primary),bodyweight=eq=='body only',equipment=eq,movementType=' · '.join(filter(None,[item.get('force'),item.get('mechanic')])),aliases=sorted(set(als)),primaryMuscles=primary,secondaryMuscles=item.get('secondaryMuscles',[]),instructions=[t for t in item.get('instructions',[]) if t.strip()])
        converted.append(dict(id=snap['id'],recordID=item['id'],quality='Community text dataset; source instructions, not individually safety-reviewed.',exercise=snap))
    src=dict(id='free-exercise-db',name='Free Exercise DB',url='https://github.com/yuhonas/free-exercise-db',license='Unlicense',licenseURL=f'https://github.com/yuhonas/free-exercise-db/blob/{COMMIT}/LICENSE.md',attribution='Free Exercise DB by yuhonas and contributors; public-domain dedication/Unlicense. Text only; no images or videos.',downloadURL=EXERCISE_URL,sha256=sha(sources/'exercises.json'))
    write(out/'exercises-v1.json',dict(schemaVersion=1,release=COMMIT,source=src,foods=[],exercises=converted))
    shutil.copyfile(sources/'EXERCISE_LICENSE.md',out/'EXERCISE_LICENSE.txt')
    report=dict(foodCount=len(result),exerciseCount=len(converted),excludedMissingMacros=excluded,sourceFoodCount=len(foods),sourceArchiveBytes=archive.stat().st_size,sourceExpandedBytes=sum(x.file_size for x in z.infolist()),files={p.name:dict(bytes=p.stat().st_size,sha256=sha(p)) for p in sorted(out.glob('*')) if p.is_file() and p.name in ['foods-v1.json','exercises-v1.json','EXERCISE_LICENSE.txt']})
    write(out/'generation-report.json',report)
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--sources',type=Path,required=True); parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parent.parent/'PersonalFitness/Resources/Catalogs')
    args=parser.parse_args();generate(args.sources,args.output)
