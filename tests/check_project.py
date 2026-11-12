"""Static validation for source package; does NOT replace Garmin SDK compilation."""
from pathlib import Path
from xml.etree import ElementTree as ET
import re

project = Path(__file__).resolve().parents[1]
for x in ("manifest.xml", "resources/strings.xml", "resources/settings.xml", "resources/properties.xml", "resources/drawables/drawables.xml"):
    ET.parse(project/x)

files = {x.name: x.read_text(encoding="utf-8") for x in (project/"source").glob("*.mc")}
assert {"Config.mc", "FieldData.mc", "StormGuard.mc", "SolarRings7X.mc"} == set(files)
manifest=(project/"manifest.xml").read_text(encoding="utf-8")
assert 'fenix7xpro' in manifest and 'fenix7xpronowifi' in manifest
assert 'SensorHistory' in manifest and 'Positioning' in manifest

# Basic structural checks of Monkey C source, ignoring comments and string content.
for name, content in files.items():
    stripped = re.sub(r'//[^\n]*', '', content)
    stripped = re.sub(r'"(?:\\.|[^"\\])*"', '""', stripped)
    for left, right in (("{", "}"), ("(", ")"), ("[", "]")):
        count = 0
        for ch in stripped:
            if ch == left: count += 1
            if ch == right: count -= 1
            assert count >= 0, (name, left, right, "early closure")
        assert count == 0, (name, left, right, "unbalanced")

config=files["Config.mc"]
data=files["FieldData.mc"]
face=files["SolarRings7X.mc"]
storm=files["StormGuard.mc"]
ids=list(map(int,re.findall(r'if \(id == (\d+)\)', data)))
assert set(ids)==set(range(35)), ("field IDs",set(range(35))-set(ids))
assert 'i <= 34' in config
for key in ('top1','topMid','top2','ring1','ring2','ring3','ring4','bottomMain','bottomMini'):
    assert f'"{key}"' in config and f'"{key}"' in face
for key in ('alertOn','alertDrop','altFilter'):
    assert f'"{key}"' in config and f'"{key}"' in storm
assert 'getSettingsView()' in face
assert 'Properties.setValue' in config and 'Properties.getValue' in config
assert ':period => new Time.Duration(10800)' in storm
assert 'maxAlt - minAlt' in storm
settings_xml=ET.parse(project/"resources/settings.xml").getroot()
properties_xml=ET.parse(project/"resources/properties.xml").getroot()
setting_ids=[el.attrib['propertyKey'].split('.')[-1] for el in settings_xml.findall('setting')]
property_ids=[el.attrib['id'] for el in properties_xml.findall('property')]
assert len(setting_ids)==len(property_ids)==16
assert set(setting_ids)==set(property_ids)
assert sum(len(el.find('settingConfig').findall('listEntry'))==35 for el in settings_xml.findall('setting'))==9
assert 'D1F8E1A4B7FC45BD91E8F0A0959041BF' in manifest
assert 'version="2.2.0"' in manifest
assert 'ringField(dc, 85, 151' in face and 'ringField(dc, 195, 208' in face
assert 'moonFraction' in data
print("OK: XML, 35 IDs, 9 slots, settings, storm, moon, 2x2 rings, syntax.")
print("Note: does not compile Monkey C or run Garmin SDK simulator.")
