from pathlib import Path
from xml.etree import ElementTree as ET
p=Path(__file__).resolve().parents[1]
for rel in ('manifest.xml','resources/strings.xml','resources/settings/properties.xml','resources/settings/settings.xml','resources/drawables/drawables.xml'):
    ET.parse(p/rel)
s=(p/'source/SolarRings7X.mc').read_text()
assert 'ringData(dc, 89, 144' in s and 'ringData(dc, 191, 144' in s
assert 'ringData(dc, 89, 194' in s and 'ringData(dc, 191, 194' in s
assert 'separator(dc, 47, 233, 218)' in s
assert 'drawDigitalValue(' in s and 'metricIcon(' in s
assert 'version="2.4.0"' in (p/'manifest.xml').read_text()
props=ET.parse(p/'resources/settings/properties.xml').getroot()
settings=ET.parse(p/'resources/settings/settings.xml').getroot()
assert len(props.findall('property'))==16
assert len(settings.findall('.//setting'))==16
print('Static checks passed. Garmin SDK and watch testing still required.')
