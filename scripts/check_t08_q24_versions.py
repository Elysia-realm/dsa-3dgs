"""Protocol-only reheadered payload sweep, with cross-version rejection in both DMAs."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t08_q24_compact import OUT, BUILD, LOCAL, edit, freeze
from scripts.t08_common import BASE, read, save, sha, run_logged


def check(version):
    d = OUT / 'protocol' / f'v{version}'
    work = LOCAL / 'protocol' / f'v{version}'
    d.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'verification/rtl/tb_t08_attribute_dma.sv'
    bench = d / source.name
    text = source.read_text()
    compressed, raw = (1, 0) if version == 1 else (2, 3)
    if version == 2:
        text = edit(text, 'formats==1', 'formats==2')
        text = edit(text, "request(64'h2000,0,2);", "request(64'h2000,0,1);")
        text = edit(text, "request(64'h2000,0,1);accept_ar", "request(64'h2000,0,2);accept_ar")
        for address, gid, count in [('2008', 0, 1), ('fffffffffffffff0', 1, 1), ('2000', 0, 2)]:
            text = edit(text, f"request(64'h{address},{gid},0);", f"request(64'h{address},{gid},3);", count)
    header_tests = []
    # Opposite version, both compact and canonical raw. Wrong raw degree is also illegal.
    other_version = 3 - version
    for hdr in (0xc8 | other_version << 8, 0x3cc8 | other_version << 8, 0x04c8 | version << 8):
        header_tests.append(f"request(64'h2000,0,{compressed});accept_ar(64'h2000,1);"
                            f"send_r(128'h{hdr:04x},1,0,0);finish_response(1,'0);"
                            "if(error_status_o!=2)$fatal;clear_error();")
    anchor = '// Early RLAST'
    text = edit(text, anchor, '\n    '.join(header_tests) + '\n    ' + anchor)
    freeze(bench, edit(text, 'axi4_t08_attribute_read_engine dut', "axi4_t08_attribute_read_engine #(.EARLY_ADVANCE(1'b1)) dut"))
    original = BASE / 'dma_20261107'
    report = read(original/'report.json')
    expected = original/'expected.memh'
    assert sha(expected) == report['expected_sha256'] and sha(original/'input.memh') == report['vectors_sha256']
    vectors = []
    for line in (original/'input.memh').read_text().splitlines():
        value = int(line, 16)
        mode = value >> 1156
        assert mode in (0, 1)
        if mode:
            assert (value >> 8) & 3 == 1
            value = (value & ~(3 << 8)) | (version << 8)
        value = (value & ((1 << 1156)-1)) | ((compressed if mode else raw) << 1156)
        vectors.append(f'{value:0290x}\n')
    inputs = d/'input.memh'
    freeze(inputs, ''.join(vectors))
    rtl = ROOT/'rtl/dma' if version == 1 else BUILD
    files = [rtl/'t08_attribute_decoder.sv', rtl/'axi4_t08_attribute_read_engine.sv', bench]
    verilator = read(BASE/'build/native/binary.json')['command'][0]
    run_logged([verilator, '--binary', '--build','-j','2','--timing','--assert','-Wno-fatal',
                '--top-module',bench.stem,'--Mdir',str(work),'-o','simulation',*map(str,files)], d/'build.log')
    execution = run_logged([str(work/'simulation'), f'+N={len(vectors)}', f'+INPUT={inputs}', f'+EXPECTED={expected}'], d/'run.log')
    text = (d/'run.log').read_text()
    assert f'PASS T08 attribute DMA data_records={len(vectors)} control_cases=12' in text
    assert f"beats={report['axi_data_beats']} " in text
    return dict(version=version, records=len(vectors), controls=12, beats=report['axi_data_beats'],
                execution=execution, elf_sha256=sha(work/'simulation'),
                sha256={str(p.relative_to(ROOT)):sha(p) for p in [*files,inputs,expected,Path(__file__)]})


if __name__ == '__main__':
    results = [check(version) for version in (1,2)]
    save(OUT/'protocol/report.json', dict(results=results, signed_off=False,
         scope='Independent v1 and v2 builds. Transport bit patterns only; numerical Q24 equivalence checked by native frames.'))
