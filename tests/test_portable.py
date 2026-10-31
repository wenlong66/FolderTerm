"""Resource/static checks and shell-escaping reference tests, NOT Swift execution."""
import pathlib
import plistlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class PortableTests(unittest.TestCase):
    def test_plist_and_entitlement(self):
        with (ROOT / 'Resources/Info.plist').open('rb') as f:
            info = plistlib.load(f)
        with (ROOT / 'Resources/Toolbar.entitlements').open('rb') as f:
            entitlements = plistlib.load(f)
        with (ROOT / 'Resources/Toolbar-Info.plist').open('rb') as f:
            helper = plistlib.load(f)
        self.assertNotIn('NSAppleEventsUsageDescription', info)
        self.assertNotIn('LSUIElement', info)
        self.assertTrue(helper['NSAppleEventsUsageDescription'])
        self.assertTrue(helper['LSUIElement'])
        self.assertEqual(entitlements, {'com.apple.security.automation.apple-events': True})

    def test_shell_quote_reference_vectors(self):
        # Reference algorithm matching Core.swift; native test.sh runs actual Swift
        # separately when a compiler exists. Execute only this controlled printf,
        # never a user's configurable command or Terminal automation.
        paths = ['/tmp/hello world', '/tmp/中文 🚀', "/tmp/O'Reilly", '/tmp/$HOME;echo bad',
                 '/tmp/`uname`', '/tmp/a\nb', '/tmp/"quoted"', '/tmp/$(echo bad)', '/tmp/\\backslash',
                 '/tmp/%PATH%', '/tmp/a\rname', '/tmp/a\tname']
        for path in paths:
            with self.subTest(path=path):
                quoted = "'" + path.replace("'", "'\\''") + "'"
                result = subprocess.run(['/bin/bash', '-c', "printf '%s' " + quoted], check=True, capture_output=True)
                self.assertEqual(result.stdout.decode(), path)
                self.assertEqual(result.stderr, b'')

    def test_no_shell_interpolated_applescript(self):
        source = (ROOT / 'Sources/Automation.swift').read_text()
        self.assertIn('NSAppleEventDescriptor(string: command)', source)
        self.assertIn('script.executeAppleEvent(event', source)
        self.assertNotIn('Process()', source)
        scripts = '\n'.join(p.read_text() for p in (ROOT / 'Resources').glob('*.applescript'))
        self.assertNotIn('System Events', scripts)
        self.assertNotIn('do shell script', scripts)
        self.assertNotIn('keystroke', scripts)

    def test_build_script_syntax(self):
        subprocess.run(['/bin/bash', '-n', str(ROOT / 'scripts/build.sh')], check=True)
        subprocess.run(['/bin/bash', '-n', str(ROOT / 'scripts/test.sh')], check=True)

    def test_resource_names_match(self):
        for name in ['Finder', 'Terminal', 'iTerm2']:
            self.assertTrue((ROOT / 'Resources' / (name + '.applescript')).is_file())
        source = (ROOT / 'Sources/ToolbarAction.swift').read_text()
        self.assertLess(source.index('let folder = try automation.currentFolder()'), source.index('try automation.open(command:'))

    def test_main_routes_only_to_configuration(self):
        source = (ROOT / 'Sources/main.swift').read_text()
        self.assertIn('lifecycle.didLaunch()', source)
        self.assertIn('lifecycle.didReopen()', source)
        for forbidden in ['Automation()', 'openCurrentFolder', 'modifierFlags', 'configured', 'open(command:', 'currentFolder()']:
            self.assertNotIn(forbidden, source)
        build = (ROOT / 'scripts/build.sh').read_text()
        main_command = build.split('xcrun swiftc', 2)[1]
        self.assertNotIn('Automation.swift', main_command)
        self.assertNotIn('ToolbarAction.swift', main_command)

if __name__ == '__main__':
    unittest.main(verbosity=2)
