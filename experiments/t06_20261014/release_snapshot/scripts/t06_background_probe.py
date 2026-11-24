"""Short liveness probe for an independently launched Windows test worker."""
import json,os,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'tmp/t06_background_probe.json'
out.write_text(json.dumps({'status':'STARTED','pid':os.getpid()}))
time.sleep(20)
out.write_text(json.dumps({'status':'FINISHED','pid':os.getpid()}))
