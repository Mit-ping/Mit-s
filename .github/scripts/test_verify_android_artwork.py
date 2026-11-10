from io import BytesIO
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import zipfile
from PIL import Image
from verify_android_artwork import verify_artwork


class ArtworkTest(unittest.TestCase):
    def test_shortened_paths_and_obfuscated_names_still_require_the_real_artwork(self):
        def png(color):
            data = BytesIO()
            Image.new('RGBA', (4, 4), color).save(data, format='PNG')
            return data.getvalue()
        expected = png('green')
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            def pack(image):
                with zipfile.ZipFile(apk, 'w') as archive:
                    archive.writestr('res/a.xml', '')
                    archive.writestr('res/b.xml', '')
                    archive.writestr('res/c.png', image)
            outputs = {
                'resources': 'resource 0x7f080001 mipmap/obfuscated\n () (file) res/a.xml type=XML\n'
                             'resource 0x7f080002 drawable/obfuscated\n () (file) res/b.xml type=XML\n'
                             'resource 0x7f080003 drawable/obfuscated\n () (file) res/c.png type=PNG\n',
                'AndroidManifest.xml': 'E: application (line=1)\n  A: android:icon(0x01010002)=@0x7f080001\n  A: android:roundIcon(0x0101052c)=@0x7f080001\n  E: service\n    A: android:icon(0x01010002)=@0x7f080099',
                'res/a.xml': 'A: android:drawable(0x01010199)=@0x7f080002',
                'res/b.xml': 'A: android:src(0x01010119)=@0x7f080003',
            }
            def run(args, **kwargs):
                return SimpleNamespace(stdout=outputs[args[2] if args[2] == 'resources' else args[4]])
            with patch('verify_android_artwork.subprocess.run', side_effect=run):
                pack(expected)
                verify_artwork(apk, 'aapt2', expected)
                pack(png('red'))
                with self.assertRaises(AssertionError):
                    verify_artwork(apk, 'aapt2', expected)
                pack(expected)
                outputs['res/b.xml'] = 'A: android:src(0x01010119)=@0x7f080099'
                with self.assertRaises(AssertionError):
                    verify_artwork(apk, 'aapt2', expected)


if __name__ == '__main__':
    unittest.main()
