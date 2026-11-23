import pathlib, shutil, subprocess, re
r=pathlib.Path('/tmp/tvbox-serverless'); u=pathlib.Path('/tmp/danmu-upstream')
v=r/'ThirdParty/danmu_api'; v.mkdir(parents=True,exist_ok=True)
subprocess.run(['git','-C',str(u),'archive','e78bfe4fa4421816b413390f4eb703d3f6f7ecda','--output=/tmp/upstream-source.tar'],check=True)
shutil.unpack_archive('/tmp/upstream-source.tar',v)
# Shipping no cross-client confidential credentials, even in unused code.
s=u.joinpath('dist/logvar-danmu.js').read_text()
a=s.index('var RenrenSource = class'); b=s.index('\n// ',a)
s=s[:a]+'''var RenrenSource = class extends BaseSource { async search(){return [];} async getDetail(){return [];} };\n'''+s[b:]
a=s.index('const { setTimeout: customSetTimeout'); b=s.index('\nclass Headers',a)
s=s[:a]+'''const setTimeout = (callback, delay=0) => __nativeTimer(callback, delay);
const clearTimeout = id => __nativeClearTimer(id);
'''+s[b:]
s=s.replace("const baseWithoutPath = base.replace(/\\/[^\\/]*$/, '');\n        this._url = baseWithoutFile", "const baseWithoutFile = base.replace(/\\/[^\\/]*$/, '');\n        this._url = baseWithoutFile")
s=s.replace("this._url = baseWithoutPath + url;", "this._url = base.match(/^[^:]+:\\/\\/[^/]+/)[0] + url;")
p=r/'tvbox/Danmaku/Resources';p.mkdir(exist_ok=True)
p.joinpath('logvar-danmu.js').write_text(s)
shutil.copy('/var/minis/workspace/serverless-danmaku-proof/package-lock.json',v/'package-lock.json')
shutil.copy(u/'package.json',v/'package.json')
shutil.copy(u/'LICENSE',p/'AGPL-3.0.txt')
# Corresponding source includes exact original, plus auditable patch script (repository build tool).
(r/'tools').mkdir(exist_ok=True)
shutil.copy(__file__,r/'tools/prepare_danmaku.py')
(r/'NOTICE-DANMAKU.md').write_text('''# Licensing and corresponding source\n\nOriginal TVBox MIT copyright and LICENSE remain unchanged. The combined distributed application incorporating danmu_api is conveyed under GNU AGPL-3.0 (not an isolated-module exception). Full upstream corresponding source at e78bfe4fa4421816b413390f4eb703d3f6f7ecda is in ThirdParty/danmu_api, including build-forward-widget.js, forward, dependencies and pinned package-lock.json (zod 3.25.76). TVBox native bridge/UI/build changes are provided in this same public branch. AGPL text is bundled in the application.\n\nRebuild upstream with npm ci && npm run build-forward-widget from ThirdParty/danmu_api. Native adaptation: replace immediate Promise timer shim with native delayed timers, fix URL relative resolution and remove RenrenSource implementation from shipped bundle; exact adaptation script tools/prepare_danmaku.py documents transformations (set repository paths locally). Build iOS using xcodegen generate and the macOS Actions workflow. No remote script evaluation, server or public proxy. Renren excluded: only verified route used cross-client signed fallback; Tudou not independently verified. Bilibili remains partial and is not enabled online here; local XML import stays available.\n''')
print('prepared',len(s))
