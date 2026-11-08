"""Run deterministic client regressions on stock Lua 5.1.

Uses lupa==2.8 when installed; otherwise a Lua 5.1 interpreter on PATH
(lua5.1, lua51 or lua) or the LUA51 environment variable."""
from pathlib import Path
import os, shutil, subprocess, sys
root=Path(__file__).resolve().parents[1]
results=root/'Tests/test-results.txt'
prelude='table.pack=table.pack or function(...) return {n=select("#",...),...} end'
try:
 from lupa.lua51 import LuaRuntime
except ImportError:
 LuaRuntime=None
if LuaRuntime:
 runtime=LuaRuntime();lines=[]
 def log(*values):
  line=' '.join(str(value) for value in values);lines.append(line);print(line)
 runtime.globals().print=log
 runtime.globals().VMM_ADDON_PATH=root.as_posix()+'/'
 runtime.execute(prelude)
 runtime.execute('dofile('+repr((root/'Tests/test_addon.lua').as_posix())+')')
 results.write_text('\n'.join(lines)+'\n',encoding='utf-8')
else:
 lua=os.environ.get('LUA51') or next((shutil.which(n) for n in ('lua5.1','lua51','lua') if shutil.which(n)),None)
 if not lua: sys.exit('Install lupa==2.8 or a Lua 5.1 interpreter (set LUA51=path)')
 setup="VMM_ADDON_PATH="+repr(root.as_posix()+'/')+";"+prelude
 run=subprocess.run([lua,'-e',setup,str(root/'Tests/test_addon.lua')],capture_output=True,text=True,cwd=root)
 print(run.stdout,end='');print(run.stderr,end='',file=sys.stderr)
 results.write_text(run.stdout,encoding='utf-8')
 sys.exit(run.returncode)
