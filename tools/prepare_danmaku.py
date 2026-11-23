#!/usr/bin/env python3
"""After npm ci && npm run build-forward-widget in ThirdParty/danmu_api, adapt locally."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = root / 'ThirdParty/danmu_api/dist/logvar-danmu.js'
s = source.read_text()
a = s.index('const { setTimeout: customSetTimeout')
b = s.index('\nclass Headers', a)
s = s[:a] + 'const setTimeout = (callback, delay=0) => __nativeTimer(callback, delay);\nconst clearTimeout = id => __nativeClearTimer(id);\n' + s[b:]
s = s.replace("const baseWithoutPath = base.replace(/\\/[^\\/]*$/, '');\n        this._url = baseWithoutFile", "const baseWithoutFile = base.replace(/\\/[^\\/]*$/, '');\n        this._url = baseWithoutFile")
s = s.replace('this._url = baseWithoutPath + url;', "this._url = base.match(/^[^:]+:\\/\\/[^/]+/)[0] + url;")
(root / 'tvbox/Danmaku/Resources/logvar-danmu.js').write_text(s)
print('Adapted bundled-only iOS JS runtime')
