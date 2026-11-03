"""Check the serializer phase-data exception against routed port records."""
from pathlib import Path
import tempfile
from build_td import verify_phase_sampling, ROOT

GOOD = r'''
EG_PHY_MSLICE #(.DFFMODE("FF"),.CLKMUX("CLK"),.CEMUX("1"),.REG0_SD("MI"),.REG1_SD("MI")) \serial/pix_sync_reg_syn_4  (
 .clk(\serial/clk_5x ),
 .mi({\serial/pix_meta ,pix_clk}),
 .q({\serial/pix_sync ,\serial/pix_meta }));
EG_PHY_LSLICE #(.DFFMODE("FF")) other (.clk(pix_clk),.mi({a,b}));
'''

SPLIT = r'''
EG_PHY_MSLICE #(.DFFMODE("FF"),.CLKMUX("CLK"),.CEMUX("1"),.REG0_SD("MI"),.REG1_SD("MI")) warmup (
 .clk(\serial/clk_5x ),.mi({1'b1,pix_clk}),.q({\serial/phase_warmup [0],\serial/pix_meta }));
EG_PHY_MSLICE #(.DFFMODE("FF"),.CLKMUX("CLK"),.CEMUX("1"),.REG0_SD("MI"),.REG1_SD("MI")) second (
 .clk(\serial/clk_5x ),.mi({\serial/pix_sync ,\serial/pix_meta }),.q({\serial/pix_prev ,\serial/pix_sync }));
'''


def main():
    with tempfile.TemporaryDirectory(prefix="phase_audit_", dir=ROOT/"build") as folder:
        netlist = Path(folder)/"netlist.v"
        rejected = 0
        for good in (GOOD, SPLIT, GOOD.replace('EG_PHY_MSLICE','EG_PHY_LSLICE'), SPLIT.replace('EG_PHY_MSLICE','EG_PHY_LSLICE')):
            netlist.write_text(good)
            assert verify_phase_sampling(netlist)
            mutations = [good+'\nBAD other (.d(pix_clk));\n',
                         good.replace('serial/clk_5x', 'wrong_clock'),
                         good.replace('serial/pix_meta', 'wrong_data'),
                         good.replace('.REG0_SD("MI")', '.REG0_SD("F")'),
                         good.replace('.CLKMUX("CLK")', '.CLKMUX("INV")'),
                         good.replace('.CEMUX("1")', '.CEMUX("CE")'),
                         good.replace('.DFFMODE("FF")', '.DFFMODE("LATCH")'),
                         good + good,
                         good.replace(r'.q({\serial/pix_sync ,\serial/pix_meta })', r'.q({\serial/pix_meta ,\serial/pix_sync })') if '.q({\\serial/pix_sync ,\\serial/pix_meta })' in good else
                         good.replace(".mi({1'b1,pix_clk})", ".mi({pix_clk,pix_clk})")]
            for bad in mutations:
                netlist.write_text(bad)
                assert not verify_phase_sampling(netlist), bad
                rejected += 1
        assert verify_phase_sampling(ROOT/'build/td/audit_physical_netlist.v')
    print(f"PASS phase audit: MSLICE/LSLICE packed/split two-stage MI-to-Q lanes and actual routed netlist accepted; {rejected} extra/wrong-source/clock/lane/register-mode mutations rejected")


if __name__ == "__main__":
    main()
