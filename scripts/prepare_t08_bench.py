"""Derive a diagnostic harness without modifying T07 evidence or production RTL."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t08_common import BASE, read, save, sha


def main():
    original = ROOT / 'verification/rtl/tb_t07_workload.sv'
    assert sha(original) == read(BASE / 'baseline_snapshot/manifest.json')[str(original.relative_to(ROOT))]
    s = original.read_text().replace('tb_t07_workload', 'tb_t08_diagnostic')
    # Observation only. All data, sort, render and AXI checks remain inherited.
    needle = '  integer state_pending_beats[0:3];'
    assert s.count(needle) == 1
    s = s.replace(needle, '''  longint unsigned t08_observation_cycles=0;
  always @(posedge clk_i) if(rst_ni)begin
    t08_observation_cycles<=t08_observation_cycles+1;
    if(t08_observation_cycles!=0&&t08_observation_cycles%10000000==0)begin
      $display("T08_PROGRESS cycles=%0d mean_beats=%0d attribute_beats=%0d qsu_reads=%0d qsu_writes=%0d commits=%0d skipped=%0d",
        t08_observation_cycles,measure_mean_beats,measure_attr_beats,measure_qsu_reads,measure_qsu_writes,perf_commit_count_o,t07_skipped);
      $fflush();
    end
  end
''' + needle)
    target = ROOT / 'verification/rtl/tb_t08_diagnostic.sv'
    if target.exists():
        assert target.read_text() == s, 'Refuse to overwrite an edited diagnostic bench'
    else:
        target.write_text(s)
    save(BASE / 'bench_derivation.json', dict(original=str(original), original_sha256=sha(original),
         target=str(target), target_sha256=sha(target), generator_sha256=sha(Path(__file__)),
         changes=['module name', 'testbench-only progress counter and log flush'],
         production_RTL_changed=False, AXI_model_changed=False))
    print(target)


if __name__ == '__main__':
    main()
