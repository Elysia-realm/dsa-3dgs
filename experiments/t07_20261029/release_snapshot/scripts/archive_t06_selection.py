"""Pin pre-IRQ-check T06 selection artifacts, never relabel them as release."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t06_20261014'
def main():
    expected=json.loads((BASE/'real_subset/bonsai/pipe1_m0_ideal/result.json').read_text())['source_sha256']
    for f,h in expected.items():
        data=(ROOT/f).read_bytes()
        if f=='verification/rtl/tb_real_dma_workload.sv':
            data=data.replace(b"      apb_write(12'h02c,3);\n",b'')
            data=data.replace(b'(qsu_requested?dut.qsu_stats[31:0]:total_workload_count)*9',b'total_workload_count*9')
            data=data.replace(b'      if(!irq_o||!dut.done_sticky_q)$fatal(1,"QSU completion/IRQ missing");\n',b'')
        assert hashlib.sha256(data).hexdigest()==h,f
        target=BASE/'subset_selection_snapshot'/f;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    print('PINNED',len(expected))
if __name__=='__main__':main()
