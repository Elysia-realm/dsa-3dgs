"""Freeze before editing the bounded two-bubble DMA candidate."""
import sys,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,read,save,sha,production_sources
def main():
    out=BASE/'early_advance_20261107';assert not (out/'edit.json').exists()
    m=production_sources()
    for f,h in m.items():
        p=out/'source_before'/f;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/f,p)
    save(out/'source_before/manifest.json',m)
    p=ROOT/'rtl/dma/axi4_t08_attribute_read_engine.sv';s=p.read_text()
    s=s.replace('parameter int unsigned ADDR_W=64,ID_W=2,GID_W=32,',"parameter bit EARLY_ADVANCE=1'b0,\n  parameter int unsigned ADDR_W=64,ID_W=2,GID_W=32,",1)
    s=s.replace('logic dec_s_ready,dec_valid', 'logic last_to_decoder;logic[1151:0]decoder_packet;\n  logic dec_s_ready,dec_valid',1)
    s=s.replace('assign m_axi_rready_o=state_q==S_R||state_q==S_ERROR_DRAIN;',
      "assign m_axi_rready_o=(state_q==S_R&&(!EARLY_ADVANCE||!compressed_q||header_q||remaining_q!=1||dec_s_ready))||state_q==S_ERROR_DRAIN;\n  assign last_to_decoder=EARLY_ADVANCE&&state_q==S_R&&compressed_q&&!header_q&&remaining_q==1&&!r_error;\n  always_comb begin decoder_packet=record_q;if(last_to_decoder)decoder_packet[total_q*128+:128]=m_axi_rdata_i;end")
    s=s.replace('.s_valid_i(state_q==S_DECODE),.s_ready_o(dec_s_ready),.s_packet_i(record_q)',
      '.s_valid_i(state_q==S_DECODE||(last_to_decoder&&m_axi_rvalid_i)),.s_ready_o(dec_s_ready),.s_packet_i(decoder_packet)')
    s=s.replace('S_R:if(m_axi_rvalid_i)begin','S_R:if(m_axi_rvalid_i&&m_axi_rready_o)begin')
    s=s.replace('else state_q<=S_NEXT;', 'else state_q<=EARLY_ADVANCE?S_AR:S_NEXT;')
    s=s.replace('state_q<=compressed_q?S_DECODE:S_RSP;', 'state_q<=compressed_q?(EARLY_ADVANCE?S_DECODE_WAIT:S_DECODE):S_RSP;')
    s=s.replace("else if(state_q==S_R&&m_axi_rvalid_i&&!r_error)","else if(state_q==S_R&&m_axi_rvalid_i&&m_axi_rready_o&&!r_error)")
    p.write_text(s)
    p=ROOT/'rtl/gs_accel_system_top.sv';s=p.read_text()
    s=s.replace("parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,","parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,\n    parameter bit ATTR_DMA_EARLY_ADVANCE=1'b0,",1)
    s=s.replace('axi4_t08_attribute_read_engine #(', 'axi4_t08_attribute_read_engine #(.EARLY_ADVANCE(ATTR_DMA_EARLY_ADVANCE),',1);p.write_text(s)
    save(out/'edit.json',dict(source_before=m,source_after=production_sources(),signed_off=False))
if __name__=='__main__':main()
