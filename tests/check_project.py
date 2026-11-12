from pathlib import Path
import xml.etree.ElementTree as ET
import re
p = Path(__file__).resolve().parents[1]
for f in ('manifest.xml', 'resources/strings.xml', 'resources/settings/properties.xml', 'resources/settings/settings.xml', 'resources/drawables/drawables.xml'):
    ET.parse(p / f)
face = (p/'source/SolarRings7X.mc').read_text()
manifest=(p/'manifest.xml').read_text()
assert 'version="2.5.0"' in manifest
assert 'id="D1F8E1A4B7FC45BD91E8F0A0959041BF"' in manifest
assert 'Gfx.FONT_' not in face, 'Stock fonts reintroduce variable height/overlap'
assert 'iconBattery(dc, 112, 263)' in face
assert 'setting("alertOn", false)' in face
assert 'iconStorm(dc, 203, 262)' in face
assert 'pixelText(dc, cx, cy+2, value, 47' in face
assert 'ring(dc, 86, 145' in face and 'ring(dc, 194, 145' in face
assert 'ring(dc, 86, 203' in face and 'ring(dc, 194, 203' in face
# center spacing 58 > diameter 52; footer begins 235, below ring max y229
assert 203-145 >= 2*26 and 203+26 < 235
# width of 6 3x5 digits in 47 pixels (scale 2) is 46
assert (6*4-1)*2 <= 47
props = ET.parse(p/'resources/settings/properties.xml').getroot()
settings = ET.parse(p/'resources/settings/settings.xml').getroot()
prop_map={x.get('id'):x for x in props.findall('property')}
settings_list = settings.findall('setting')
assert len(prop_map)==16 and len(settings_list)==16
assert len(settings.findall('group')) == 0
for x in settings_list:
    key=x.get('propertyKey','').replace('@Properties.','')
    assert key in prop_map, key
assert prop_map['alertOn'].text=='false'
assert not (p/'resources/properties.xml').exists()
assert not (p/'resources/settings.xml').exists()
print('Static validation: 2x2 nonoverlap, six-digit steps, 16 mobile settings, storm off')
