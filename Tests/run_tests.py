"""Run deterministic client regressions with lupa==2.8 / stock Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
runtime=LuaRuntime()
lines=[]
def log(*values):
 line=' '.join(str(value) for value in values)
 lines.append(line);print(line)
runtime.globals().print=log
runtime.globals().VMM_ADDON_PATH=root.as_posix()+'/'
runtime.execute('table.pack=table.pack or function(...) return {n=select("#",...),...} end')
runtime.execute('dofile('+repr((root/'Tests/test_addon.lua').as_posix())+')')
(root/'Tests/test-results.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
