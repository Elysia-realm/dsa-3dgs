import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,read,save,sha,frozen
suite=Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite'
files=[suite/'bin/yosys',suite/'libexec/yosys',suite/'bin/yosys-abc',suite/'libexec/yosys-abc',suite/'bin/verilator',suite/'libexec/verilator_bin',Path.home()/'eda/opt/opensta/bin/sta']
rows=[]
for p in files:
    if p.is_file():rows.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)))
versions={}
for key,cmd in [('yosys',[str(suite/'bin/yosys'),'-V']),('abc',[str(suite/'bin/yosys-abc'),'-c','version']),('verilator',[str(suite/'bin/verilator'),'--version']),('iverilog',['iverilog','-V']),('g++',['g++','--version']),('python',[sys.executable,'--version']),('kernel',['uname','-r'])]:
    r=subprocess.run(cmd,capture_output=True,text=True);assert r.returncode==0
    versions[key]=r.stdout+r.stderr
save(BASE/'toolchain.json',dict(files=rows,versions=versions,oss_archive=read(BASE/'oss_linux_archive.json')))
observations={
 'bonsai':'盆栽、台面和背景结构可辨识，非近似纯色；低分辨率细节有限。',
 'counter':'台面物品及明暗分布可辨识，非近似纯色；边缘有低分辨率锯齿。',
 'room':'家具、地板和房间结构可辨识；物体边缘细节受128宽限制。',
 'train':'列车、轨道和背景结构可辨识；细部有碎点/锯齿，未见整幅近似纯色异常。',
 'truck':'卡车、道路和周围结构可辨识；阴影及边缘有碎点，未据此宣称GT画质通过。'}
visual=[]
for n,note in observations.items():
    p=BASE/'real/full'/n;r=read(p/'result.json')
    visual.append(dict(scene=n,image=str(p/'frame.png'),png_sha256=sha(p/'frame.png'),rgb_sha256=sha(p/'frame.rgb'),independent_float_mae=r['independent_float_mae'],observation=note))
save(BASE/'visual_review.json',dict(status='REVIEWED_FIVE_LOW_RESOLUTION_FULL_MODEL_IMAGES',method='Assistant inspected all five actual PNG files using view_image; PNG payload separately checked against RTL RGB DMA bytes',images=visual,scope='Qualitative inspection and independent low-resolution math comparison; not native-resolution or GT acceptance',source_sha256=frozen()))
