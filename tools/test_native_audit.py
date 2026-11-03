"""Reject extra SDRAM clock sinks, changed SIP pads and changed clock parameters."""
from pathlib import Path
import tempfile
from build_td import ROOT, verify_native_sdram_mapping


def main():
    source = (ROOT/"build/td/audit_physical_netlist.v").read_text()
    with tempfile.TemporaryDirectory(prefix="native_audit_", dir=ROOT/"build") as folder:
        target = Path(folder)/"netlist.v"
        target.write_text(source)
        assert verify_native_sdram_mapping(target)
        mutations = [source + r"BAD sink (.d(\player/image_ram/sd_clk ));",
                     source.replace('.SIP_INFO("clk/S73")', '.SIP_INFO("clk/S74")'),
                     source.replace('.CLKC3_CPHASE(8)', '.CLKC3_CPHASE(7)'),
                     source.replace('.CLKC2_DIV(15)', '.CLKC2_DIV(10)'),
                     source.replace('.SIP_INFO("dq[31]/S48")', '.SIP_INFO("dq[31]/S49")')]
        for index, changed in enumerate(mutations):
            assert changed != source
            target.write_text(changed)
            assert not verify_native_sdram_mapping(target), index
    print("PASS native routed audit: 55 SIP pads, PLL mapping and sole clock output; five mutations rejected")


if __name__ == "__main__":
    main()
