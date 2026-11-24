"""Fail-closed tests for the large structural-netlist signedness proof."""
import tempfile,unittest
from pathlib import Path
from asic.scripts.t01_structural_width_proof import prove
ROOT=Path(__file__).resolve().parents[1]
LIB=ROOT/'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib'
YOSYS=Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite/bin/yosys'
class StructuralSignednessTests(unittest.TestCase):
    def check(self,source,valid):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'fixture.v';p.write_text(source)
            if valid:self.assertEqual(prove(p,LIB,YOSYS)['status'],'PASS_STRUCTURAL_SIGNEDNESS_INDEPENDENCE')
            else:
                with self.assertRaises(AssertionError):prove(p,LIB,YOSYS)
    def top(self,width,expr):
        return f'module t(a,y);\ninput signed [3:0] a;\noutput [{width-1}:0] y;\nassign y = {expr};\nendmodule\n'
    def test_equal_width(self):self.check(self.top(4,'a'),True)
    def test_signed_extension_rejected(self):self.check(self.top(8,'a'),False)
    def test_truncation(self):self.check(self.top(2,'a'),True)
    def test_explicit_concatenation(self):self.check(self.top(8,"{4'b0000,a}"),True)
    def test_unsigned_part_select_extension(self):self.check(self.top(8,'a[3:0]'),True)
    def test_arithmetic_rejected(self):self.check(self.top(4,"a + 4'b0001"),False)
    def test_unsized_constant_rejected(self):self.check(self.top(4,'0'),False)
    def test_out_of_range_rejected(self):self.check(self.top(4,'a[7:4]'),False)
    def test_signed_child_output_extension_rejected(self):
        self.check('module c(x,y);\ninput [3:0] x;\noutput signed [3:0] y;\nassign y = x;\nendmodule\nmodule t(a,y);\ninput [3:0] a;\noutput [7:0] y;\nc u (\n.x(a),\n.y(y)\n);\nendmodule\n',False)
    def test_signed_child_input_extension_rejected(self):
        self.check('module c(x,y);\ninput [7:0] x;\noutput [7:0] y;\nassign y = x;\nendmodule\nmodule t(a,y);\ninput signed [3:0] a;\noutput [7:0] y;\nc u (\n.x(a),\n.y(y)\n);\nendmodule\n',False)
if __name__=='__main__':unittest.main()
