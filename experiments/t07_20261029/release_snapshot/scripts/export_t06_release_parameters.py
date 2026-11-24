"""Print selected production parameters for Verilator or Yosys, never bare defaults."""
import argparse,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import profile
def main():
    p=argparse.ArgumentParser();p.add_argument('--tool',choices=['verilator','yosys'],required=True);args=p.parse_args()
    cfg=profile();params=cfg['parameters']
    if args.tool=='verilator':print(' '.join(f'-G{k}={v}' for k,v in params.items()))
    else:print('chparam '+' '.join(f'-set {k} {v}' for k,v in params.items())+' '+cfg['production_top'])
if __name__=='__main__':main()
