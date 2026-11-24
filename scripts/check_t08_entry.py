"""Entry checks for native image capacity and inherited physical address ranges."""
import subprocess
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t08_common import BASE, WORK, MAX_COUNT, MAX_PIXELS, read, save, sha, run_logged


def main():
    out = BASE / 'entry_checks'
    work = WORK / 'entry_checks'
    work.mkdir(parents=True, exist_ok=True)
    cases = [('native_capacity', MAX_COUNT, MAX_PIXELS, 0, None),
             ('original_model_capacity_native_pixels', 7000000, MAX_PIXELS, 0, None),
             ('below_region', MAX_COUNT, MAX_PIXELS, 1, 'AXI region violation'),
             ('past_region', MAX_COUNT, MAX_PIXELS, 2, 'AXI region violation'),
             ('address_wrap', MAX_COUNT, MAX_PIXELS, 3, 'AXI region violation'),
             ('zero_length', MAX_COUNT, MAX_PIXELS, 4, 'AXI region violation'),
             ('scratch_overlap', 8500000, MAX_PIXELS, 0, 'overlapping or overflowing'),
             ('output_overflow', MAX_COUNT, 9000000, 0, 'overlapping or overflowing')]
    rows = []
    for name, count, pixels, fault, message in cases:
        binary = work / (name+'.vvp')
        cmd = ['/usr/bin/iverilog','-g2012','-s','tb_t06_memory_layout',
               f'-Ptb_t06_memory_layout.MAX_COUNT={count}', f'-Ptb_t06_memory_layout.MAX_PIXELS={pixels}',
               '-o',str(binary),'verification/rtl/tb_t06_memory_layout.sv']
        run_logged(cmd, out/(name+'.build.log'))
        run = ['/usr/bin/vvp',str(binary),f'+FAULT={fault}']
        r = subprocess.run(run,cwd=ROOT,capture_output=True,text=True)
        log = out/(name+'.log')
        log.write_text(r.stdout+r.stderr)
        assert (r.returncode==0 and 'PASS T06' in r.stdout) if message is None else (r.returncode!=0 and message in r.stdout)
        rows.append(dict(name=name,command=run,returncode=r.returncode,status='PASS',
                         expected_rejection=message, log_sha256=sha(log), binary_sha256=sha(binary)))
    for row in read(BASE/'entry_budget.json')['scenes']:
        w,h = row['width'],row['height']
        n = row['gaussians']
        stride = (w*3+15)&~15
        ranges = [('camera',0x2000,224),('mean',0x01000000,n*16),('attr',0x10000000,n*144),
                  ('qsu',0x60000000,n*32),('RGB',0x70000000,stride*h),('state',0x70000000+stride*h,w*h*16)]
        for (_,base,size),(_,next_base,_) in zip(ranges,ranges[1:]):
            assert base+size <= next_base
        assert ranges[-1][1]+ranges[-1][2] <= 0x80000000
        assert stride*h <= MAX_PIXELS*16 and w*h <= MAX_PIXELS and n <= MAX_COUNT
        rows.append(dict(name=row['scene']+'_runtime_regions',status='PASS',ranges=ranges,
                         input_manifest_sha256=sha(BASE/'inputs/native'/row['scene']/'manifest.json')))
    save(out/'report.json',dict(status='PASS',results=rows,signed_off=False,
         source_sha256={f:sha(ROOT/f) for f in ['scripts/check_t08_entry.py',
           'verification/rtl/t06_memory_layout.svh','verification/rtl/tb_t06_memory_layout.sv']}))
    print('PASS: 8 native address guard cases and 5 full native workload layouts')


if __name__=='__main__':
    main()
