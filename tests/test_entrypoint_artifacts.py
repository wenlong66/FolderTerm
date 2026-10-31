"""Inspect built entry points without launching apps or sending Apple Events."""
import pathlib
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = pathlib.Path(os.environ.get('FOLDERTERM_APP_PATH', ROOT / 'build/0.4.0/FolderTerm.app')).resolve()
HELPER = APP / 'Contents/Helpers/FolderTermToolbar.app'


def info(app):
    with (app / 'Contents/Info.plist').open('rb') as f:
        return plistlib.load(f)


def entitlements(app):
    result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(app)],
                            check=True, capture_output=True)
    return plistlib.loads(result.stdout) if result.stdout.strip() else {}


class EntrypointArtifacts(unittest.TestCase):
    def test_main_has_no_automation_capability(self):
        main = info(APP)
        self.assertNotIn('NSAppleEventsUsageDescription', main)
        self.assertNotIn('com.apple.security.automation.apple-events', entitlements(APP))
        for script in ['Finder', 'Terminal', 'iTerm2']:
            self.assertFalse((APP / 'Contents/Resources' / (script + '.applescript')).exists())
        binary = APP / 'Contents/MacOS' / main['CFBundleExecutable']
        imports = subprocess.run(['nm', '-u', str(binary)], check=True,
                                 capture_output=True, text=True).stdout
        self.assertNotIn('NSAppleScript', imports)
        for forbidden in ['_CFPreferencesSetMultiple', '_AXIsProcessTrusted', '_CGEventPost', '_kill', '_system', '_posix_spawn']:
            self.assertNotIn(forbidden, imports)
        self.assertIn('_CFPreferencesSetValue', imports)
        self.assertIn('_CFPreferencesSynchronize', imports)

    def test_only_helper_carries_automation(self):
        main, helper = info(APP), info(HELPER)
        self.assertNotEqual(main['CFBundleIdentifier'], helper['CFBundleIdentifier'])
        self.assertEqual(helper['CFBundleIdentifier'], 'app.folderterm.FolderTerm.Toolbar')
        self.assertEqual(main['CFBundleShortVersionString'], helper['CFBundleShortVersionString'])
        self.assertTrue(helper['LSUIElement'])
        self.assertTrue(helper['NSAppleEventsUsageDescription'])
        self.assertTrue(entitlements(HELPER)['com.apple.security.automation.apple-events'])
        binary = HELPER / 'Contents/MacOS' / helper['CFBundleExecutable']
        imports = subprocess.run(['nm', '-u', str(binary)], check=True,
                                 capture_output=True, text=True).stdout
        self.assertIn('NSAppleScript', imports)
        for script in ['Finder', 'Terminal', 'iTerm2']:
            self.assertTrue((HELPER / 'Contents/Resources' / (script + '.applescript')).is_file())

    def test_no_external_command_url_handler(self):
        self.assertNotIn('CFBundleURLTypes', info(APP))
        self.assertNotIn('CFBundleURLTypes', info(HELPER))

    def test_bundle_can_be_relocated_with_helper_intact(self):
        with tempfile.TemporaryDirectory(prefix='relocation-', dir=ROOT / 'build') as directory:
            moved = pathlib.Path(directory) / "中文 O'Reilly FolderTerm.app"
            shutil.copytree(APP, moved, symlinks=True)
            helper = moved / 'Contents/Helpers/FolderTermToolbar.app'
            self.assertEqual(info(helper)['CFBundleIdentifier'], info(HELPER)['CFBundleIdentifier'])
            self.assertTrue((helper / 'Contents/Resources/Finder.applescript').is_file())
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(moved)],
                           check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
