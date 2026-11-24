"""Check mixed-version requests, late mode writes, recovery, and the default-off contract."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t08_dual_precision import BUILD, OUT, LOCAL
from scripts.run_t08_q24_compact import OUT as COMPACT, edit, freeze
from scripts.t08_common import BASE, read, save, sha, run_logged


def check(enabled):
    name = 'enabled' if enabled else 'default'
    out = OUT/'protocol'/name
    work = LOCAL/'protocol'/name
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    source = ROOT/'verification/rtl/tb_t08_attribute_dma.sv'
    bench = out/source.name
    text = source.read_text()
    params = ".ENABLE_Q24(1'b1)," if enabled else ''
    text = edit(text,'axi4_t08_attribute_read_engine dut',
                "axi4_t08_attribute_read_engine #("+params+".EARLY_ADVANCE(1'b1)) dut")
    text = edit(text,'format_i=3;', "format_i=fmt^2'd3;")
    text = edit(text,'formats==1&&offset==0','(formats==1||formats==2)&&offset==0')
    if enabled:
        # A formerly unsupported command now accepts a header. Verify it rejects v1.
        text = edit(text,"request(64'h2000,0,2);finish_response",
                    "request(64'h2000,0,2);accept_ar(64'h2000,1);send_r(128'h01c8,1,0,0);finish_response")
    extra = []
    if enabled:
        for fmt,bad in [(1,0x02c8),(1,0x3ec8),(2,0x3dc8),(2,0x06c8),(1,0x05c8)]:
            extra.append(f"request(64'h2000,0,{fmt});accept_ar(64'h2000,1);"
                         f"send_r(128'h{bad:x},1,0,0);finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();")
    else:
        extra.append("request(64'h2000,0,3);finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();")
    freeze(bench,edit(text,'// Early RLAST','\n    '.join(extra)+'\n    // Early RLAST'))
    files = [BUILD/'axi4_t08_attribute_read_engine.sv',BUILD/'t08_attribute_decoder.sv',bench]
    verilator = read(BASE/'build/native/binary.json')['command'][0]
    run_logged([verilator,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal',
                '--top-module',bench.stem,'--Mdir',str(work),'-o','simulation',*map(str,files)],out/'build.log')
    original = BASE/'dma_20261107'
    expected = original/'expected.memh'
    checked = read(COMPACT/'protocol/report.json')['results']
    data = []
    for row in checked:
        path = COMPACT/'protocol'/f"v{row['version']}"/'input.memh'
        for p in (path,expected):
            assert sha(p)==row['sha256'][str(p.relative_to(ROOT))]
        data.append(path.read_text().splitlines())
    assert len(data[0])==len(data[1])==6144
    rows = []
    for variant in range(2 if enabled else 1):
        d = out/str(variant)
        d.mkdir(exist_ok=True)
        inputs = d/'input.memh'
        # Adjacent legacy/compact pairs use the same precision; change it on the next pair.
        freeze(inputs,''.join(data[((i//2 + variant)%2) if enabled else 0][i]+'\n' for i in range(6144)))
        run = run_logged([str(work/'simulation'),'+N=6144',f'+INPUT={inputs}',f'+EXPECTED={expected}'],d/'run.log')
        text = (d/'run.log').read_text()
        assert f'PASS T08 attribute DMA data_records=6144 control_cases={9+len(extra)}' in text
        assert 'beats=49172 ' in text
        rows.append(dict(enabled=enabled,variant=variant,execution=run,records=6144,beats=49172,
                         controls=9+len(extra),inputs_sha256=sha(inputs),expected_sha256=sha(expected),
                         elf_sha256=sha(work/'simulation'),sources={str(p.relative_to(ROOT)):sha(p) for p in files}))
    return rows


if __name__=='__main__':
    rows=check(False)+check(True)
    save(OUT/'protocol/report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False,
         scope='Transport and format snapshot at DMA level; alternating version-tagged bit patterns at enabled setting.'))
