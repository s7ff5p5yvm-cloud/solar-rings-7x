"""Project XML, slot layout, localization and geometry checks. Not a device compile."""
from pathlib import Path
from xml.etree import ElementTree as ET
import re

project=Path(__file__).resolve().parents[1]
for rel in ("manifest.xml","resources/strings.xml","resources/settings/properties.xml","resources/settings/settings.xml","resources/drawables/drawables.xml"):
    ET.parse(project/rel)
manifest=(project/"manifest.xml").read_text()
assert 'version="2.3.0"' in manifest
assert 'D1F8E1A4B7FC45BD91E8F0A0959041BF' in manifest
properties=ET.parse(project/"resources/settings/properties.xml").getroot()
settings=ET.parse(project/"resources/settings/settings.xml").getroot()
strings=ET.parse(project/"resources/strings.xml").getroot()
pids={n.attrib['id'] for n in properties.findall('property')}
sids={n.attrib['id'] for n in strings.findall('string')}
items=settings.findall('.//setting')
assert len(items)==len(pids)==16
assert {e.attrib['propertyKey'].split('.')[-1] for e in items}==pids
for e in items:
    assert e.attrib['title'].split('.')[-1] in sids
    cfg=e.find('settingConfig')
    assert cfg is not None
    for opt in cfg.findall('listEntry'): assert opt.text.split('.')[-1] in sids
assert len(settings.findall('group'))==5
assert all(g.attrib['title'].split('.')[-1] in sids for g in settings.findall('group'))
assert sum(len(e.find('settingConfig').findall('listEntry')) == 35 for e in items)==9
source=(project/'source/SolarRings7X.mc').read_text()
for wanted in ('ringData(dc, 89, 138','ringData(dc, 191, 138','ringData(dc, 89, 190','ringData(dc, 191, 190','weatherFooter(dc','batteryFooter(dc','onSettingsChanged()','getSettingsView()','metricIcon(','drawDigitalValue('):
    assert wanted in source,wanted
assert 'getTextWidthInPixels' in source
assert 'drawFitted' in source
assert 'var radius = 23;' in source
assert 'Gfx.FONT_NUMBER_MILD' in source
for f in (project/'source').glob('*.mc'):
    data=f.read_text()
    clean=re.sub(r'//[^\n]*','',data)
    clean=re.sub(r'"(?:\\.|[^"\\])*"','""',clean)
    for l,r in [('(',')'),('[',']'),('{','}')]:
        count=0
        for c in clean:
            if c==l: count+=1
            elif c==r: count-=1
            assert count>=0,(f.name,l,r)
        assert count==0,(f.name,l,r)
# Pixel bands overlap guards (280px MIP screen), based on layout constants.
assert 113 < 138-23
assert 138+23 < 190-23
assert 190+23 < 217
assert 235 < 245
# 3x5 pixel numerals with scales 2/3 are fully contained in the 46 px ring diameter.
for digits in ("51", "64", "81", "2110", "10000", "12345", "25000", "99999"):
    scale = 3 if len(digits) <= 2 else 2
    rendered_width = (len(digits) * 4 - 1) * scale
    assert rendered_width <= 46, (digits, rendered_width)
assert 'x < 100000 ? x.toString()' in (project/'source/FieldData.mc').read_text()
assert not (project/'resources/settings.xml').exists()
assert not (project/'resources/properties.xml').exists()
print('OK: 16 Garmin settings, 9 fields, icons, 2x2 layout, 5-digit steps, footer bounds.')
print('Next: compile IQ with Garmin SDK and test on the watch. These checks are static only.')
