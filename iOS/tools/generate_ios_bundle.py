#!/usr/bin/env python3
# Generates the iOS WKWebView bundle from the extension source.
# This replicates the iOS part of generate.php for environments without PHP.
# Usage: python3 generate_ios_bundle.py [Chromium|Firefox]

import base64
import json
import mimetypes
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(ROOT, 'iOS', 'SomtodayMod', 'Resources', 'SomtodayMod-iOS.js')

MIME_OVERRIDES = {
    '.json': 'application/json',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.otf': 'font/otf',
    '.ttf': 'font/ttf',
    '.svg': 'image/svg+xml',
    '.js': 'text/javascript',
}

CUSTOM_MIME_TYPES = {
    'application/json': ['.json'],
    'font/woff': ['.woff'],
    'font/woff2': ['.woff2'],
    'font/otf': ['.otf'],
    'image/svg+xml': ['.svg'],
}


def get_mime(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in MIME_OVERRIDES:
        return MIME_OVERRIDES[ext]
    mime, _ = mimetypes.guess_type(path)
    return mime or 'application/octet-stream'


def recursive_get_files(path, source_dir):
    real_path = os.path.join(source_dir, path)
    if not os.path.exists(real_path):
        raise RuntimeError('File not found: %s' % path)
    if os.path.isdir(real_path):
        result = {}
        for name in sorted(os.listdir(real_path)):
            if name in ('.', '..'):
                continue
            result.update(recursive_get_files(os.path.join(path, name), source_dir))
        return result
    with open(real_path, 'rb') as f:
        return {path.replace('\\', '/'): f.read()}


def prepare_css(css):
    css = css.replace('\r\n', '').replace('\n', '').replace('\r', '')
    css = css.replace("'", "\\'")
    while '  ' in css:
        css = css.replace('  ', ' ')
    return css


def minify(code):
    """Minify with esbuild via npx, mirroring generate.php. Returns None on failure."""
    try:
        proc = subprocess.run(
            ['npx', 'esbuild', '--minify'],
            input=code.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            shell=True if os.name == 'nt' else False,
        )
        output = proc.stdout.decode('utf-8', 'replace')
        if proc.returncode == 0 and len(output) > 1000:
            return output.replace('\n', ' ')
    except Exception:
        pass
    return None


def main():
    source_name = sys.argv[1] if len(sys.argv) > 1 else 'Chromium'
    source_dir = os.path.join(ROOT, source_name)
    with open(os.path.join(source_dir, 'manifest.json'), 'r', encoding='utf-8') as f:
        manifest = json.load(f)
    with open(os.path.join(source_dir, 'version_info.json'), 'r', encoding='utf-8') as f:
        version_info = json.load(f)

    result = ''
    for script in manifest['content_scripts'][0]['js']:
        with open(os.path.join(source_dir, script), 'r', encoding='utf-8') as f:
            result += f.read()

    css = ''
    for style in manifest['content_scripts'][0]['css']:
        with open(os.path.join(source_dir, style), 'r', encoding='utf-8') as f:
            css += f.read()
    marker = "// [GENERATION] APPLY_STYLES"
    css_js = "tn('head', 0).insertAdjacentHTML('beforeend', '<style>%s</style>');" % prepare_css(css)
    if marker not in result:
        raise RuntimeError('Missing %s marker' % marker)
    result = result.replace(marker, css_js)

    # Collect all web-accessible resources (sounds excluded, too heavy)
    files = {}
    for resource in manifest['web_accessible_resources'][0]['resources']:
        accessible = resource.replace('/*', '')
        if accessible == 'sounds':
            continue
        files.update(recursive_get_files(accessible, source_dir))

    version_info = dict(version_info)
    version_info['platform'] = 'iOS'
    version_info['minified'] = True
    files['version_info.json'] = json.dumps(version_info).encode('utf-8')

    file_map = {}
    for path, content in files.items():
        file_map[path] = 'data:%s;base64,%s' % (get_mime(path), base64.b64encode(content).decode('ascii'))

    marker = "// [GENERATION] DEFINE_FILEMAP"
    if marker not in result:
        raise RuntimeError('Missing %s marker' % marker)
    result = result.replace(marker, 'fileMap = %s;' % json.dumps(file_map))

    # Theme bridge to the native iOS shell
    result = result.replace(
        "// [GENERATION] GECKOVIEW_SAVE_THEME",
        "if (n(theme) == false && window.webkit != null && window.webkit.messageHandlers != null && window.webkit.messageHandlers.somtodaymod != null) { window.webkit.messageHandlers.somtodaymod.postMessage({ type: 'SAVE_THEME', theme: theme }); }"
    )

    minified = minify(result)
    if minified is None:
        print('esbuild not available, writing unminified bundle')
    else:
        result = minified

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(result)
    print('Wrote %s (%.1f KB)' % (OUTPUT, len(result.encode('utf-8')) / 1024))


if __name__ == '__main__':
    main()
