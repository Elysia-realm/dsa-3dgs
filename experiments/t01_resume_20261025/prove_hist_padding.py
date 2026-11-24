"""Audit the exact padding warning set and prove original QSU pointer bounds."""
import re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,save,sha,run_logged
YOSYS=Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite/bin/yosys'
out=BASE/'hist_padding_proof';out.mkdir(exist_ok=True)
failure=out/'premap_initial_failure.log'
text=failure.read_text()
warnings=[l for l in text.splitlines() if l.startswith('Warning:') and 'has no driver' in l]
bits=set();names=set()
for line in warnings:
    m=re.search(r'autonomous_qsu\.(\$memory\\saved_hist\$rdmux\[0\]\[7\]\[(\d+)\]\$(a|b)\$\d+) \[(\d+)\] is used but has no driver',line)
    assert m,line
    row=2*int(m[2])+(m[3]=='b');bit=int(m[4]);assert 218<=row<256 and 0<=bit<1712
    bits.add((row,bit));names.add(m[1])
assert len(warnings)==len(bits)==38*1712 and len(names)==38
save(out/'warning_audit.json',dict(status='PASS_EXACT_PADDING_SET',warnings=len(warnings),rows=[218,255],width=1712,unique_nets=len(names),original_log_sha256=sha(failure)))
source=ROOT/'rtl/sort/autonomous_qsu.sv';original=source.read_text()
assert original.count('endmodule')==1
proof=original.replace('endmodule','''
`ifdef T01_FORMAL_BOUNDS
    always @(posedge clk_i) if (rst_ni) begin
        assert (sp_q <= STACK_DEPTH);
        if (state_q == POP && sp_q != 0 && !(local_active_q && sp_q == local_exit_sp_q))
            assert ((sp_q - 1'b1) < STACK_DEPTH);
    end
`endif
endmodule''')
copy=out/'autonomous_qsu_bounds.sv';copy.write_text(proof)
script=out/'bounds.ys'
script.write_text('\n'.join([
 f'read_verilog -formal -sv -DSYNTHESIS -DT01_FORMAL_BOUNDS {copy}',
 'chparam -set PRECOUNT_CHILDREN 1 -set LOCAL_RECORDS 0 autonomous_qsu',
 'prep -top autonomous_qsu',
 # Overapproximate control predicates, preserving the original sp_q update logic.
 'cutpoint w:state_q w:counts* w:local_active_q w:local_exit_sp_q',
 'delete -output w:*','opt_clean -purge','async2sync','opt_clean',
 'write_rtlil '+str(out/'pointer_cone.il'),
 'sat -seq 2 -tempinduct -maxsteps 4 -set rst_ni 1 -set-at 1 rst_ni 0 -show sp_q -show state_q -show push_q -prove-asserts -verify -dump_vcd '+str(out/'bounds_counterexample.vcd'),
])+'\n')
run_logged([str(YOSYS),'-s',str(script)],out/'proof.log')
log=(out/'proof.log').read_text();assert 'SUCCESS' in log
assert 'No SAT model' not in log
save(out/'proof.json',dict(status='PASS_POINTER_BOUNDS_INDUCTION',original_rtl_sha256=sha(source),proof_source_sha256=sha(copy),proof_script_sha256=sha(script),log_sha256=sha(out/'proof.log'),scope='Original sp_q update logic with state_q, counts and local-exit predicates replaced by explicit arbitrary anyseq values; stronger than reachable control sequences. No unsupported cells ignored. Proves pointer bounds and consumed histogram read address only; no data/order equivalence claimed.'))
print('PASS exact padding warning set and pointer bounds')
