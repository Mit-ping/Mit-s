"""Check launcher pixels through compiled references, including shortened paths."""
from io import BytesIO
import hashlib
import re
import subprocess
import zipfile


def references(text):
    return {'0x' + value.lower() for value in re.findall(r'(?:@0x|\(reference\)\s*0x)([0-9a-fA-F]{8})', text)}


def resource_entries(text):
    entries = {}
    current = None
    for line in text.splitlines():
        match = re.search(r'\bresource\s+(0x[0-9a-fA-F]{8})\s+', line)
        if match:
            current = {'files': set(), 'refs': set()}
            entries[match[1].lower()] = current
        if current is not None:
            current['files'].update(re.findall(r'\bres/[^\s\'\"]+\.(?:xml|png|webp)\b', line))
            current['refs'].update(references(line))
    return entries


def visible_pixels(data):
    from PIL import Image
    with Image.open(BytesIO(data)) as image:
        rgba = image.convert('RGBA')
        # PNG crunching may discard invisible RGB channels under alpha=0.
        visible = Image.alpha_composite(Image.new('RGBA', rgba.size, (0, 0, 0, 255)), rgba).convert('RGB')
        return image.size, hashlib.sha256(visible.tobytes()).digest()


def verify_artwork(apk, aapt2, expected_artwork):
    def dump(*args):
        return subprocess.run([str(aapt2), 'dump', *args, str(apk)], check=True, capture_output=True, text=True).stdout

    entries = resource_entries(dump('resources'))
    manifest = dump('xmltree', '--file', 'AndroidManifest.xml')
    icon_lines = []
    in_application = False
    for line in manifest.splitlines():
        if re.search(r'\bE:\s+application(?:\s|$)', line):
            in_application = True
            continue
        if in_application and re.search(r'\bE:', line):
            break
        if in_application and re.search(r':(?:roundIcon|icon)\(', line):
            icon_lines.append(line)
    assert icon_lines, 'Packaged manifest must select a launcher icon'
    icon_ids = set().union(*(references(line) for line in icon_lines))
    assert icon_ids, 'Launcher icon references are missing'
    expected = visible_pixels(expected_artwork)
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        xml_refs, pixels = {}, {}

        def matches(key, seen):
            if key in seen or key not in entries:
                return False
            seen = seen | {key}
            entry = entries[key]
            children = set(entry['refs'])
            found = False
            for path in entry['files']:
                assert path in names, f'Missing compiled resource: {path}'
                if path.endswith('.xml'):
                    if path not in xml_refs:
                        xml_refs[path] = references(dump('xmltree', '--file', path))
                    children.update(xml_refs[path])
                else:
                    if path not in pixels:
                        pixels[path] = visible_pixels(archive.read(path))
                    found |= pixels[path] == expected
            return found or any(matches(child, seen) for child in children)

        for key in icon_ids:
            assert key in entries, 'Selected launcher resource is missing'
            # Validate each density/adaptive variant, not just one fallback.
            paths = entries[key]['files']
            for path in paths:
                if path.endswith('.xml'):
                    refs = references(dump('xmltree', '--file', path))
                    assert any(matches(child, {key}) for child in refs), 'Launcher variant must render the Mit artwork'
            assert matches(key, set()), 'Launcher must render the Mit artwork'
