"""Build or verify the installable ZIP using canonical LF text sources."""
from pathlib import Path
import argparse
import zipfile
root=Path(__file__).resolve().parents[1]
addon='VoidMarkMarket'
source=root/''
skip={'.git','.github','tests','Tests','tools','dist','__pycache__'}
files={}
for path in source.rglob('*'):
 if not path.is_file(): continue
 relative=path.relative_to(source)
 if any(part in skip or part.startswith('.') for part in relative.parts): continue
 files[addon+'/'+relative.as_posix()]=path

def contents(path):
 data=path.read_bytes()
 if path.suffix.lower() in {'.lua','.toc','.xml','.md','.txt'} or path.name=='LICENSE':
  data=data.replace(b'\r\n',b'\n')
 return data

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
archive=root/'dist'/(addon+'.zip')
if not args.check:
 archive.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as output:
  for name,path in sorted(files.items()):
   info=zipfile.ZipInfo(name,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
   info.external_attr=0o100644<<16;output.writestr(info,contents(path))
with zipfile.ZipFile(archive) as output:
 assert output.testzip() is None,'ZIP integrity failure'
 assert len(output.namelist())==len(files) and set(output.namelist())==set(files),'Incorrect ZIP file list'
 for name,path in files.items(): assert output.read(name)==contents(path),'Stale ZIP source: '+name
print('PASS: '+str(len(files))+' packaged files match canonical sources: '+archive.name)
