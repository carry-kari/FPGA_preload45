"""Check physical implementation and publish a compact GUI build result."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import subprocess
import sys
from build_td import verify_native_sdram_mapping, verify_phase_sampling

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def timing_gate(text):
    values = {}
    for key in ('SWNS', 'HWNS', 'STNS', 'HTNS'):
        match = re.search(key + r':\s+(-?[\d.]+)ns', text)
        if not match or float(match[1]) < 0:
            raise ValueError(f'Timing gate failed: {key}')
        values[key] = float(match[1])
    return values

def verify(root):
    flow = root / 'hx4s20c_Runs/phy_1/hx4s20c.tcl'
    assert flow.read_bytes() == (root / 'td/gui_phy_flow.tcl').read_bytes()
    project = (root / 'hx4s20c.al').read_text(encoding='utf-8')
    assert re.search(r'<Run\b[^>]*Name="phy_1"[^>]*useDefaultScript="false"', project)
    values = timing_gate((root / 'hx4s20c_Runs/phy_1/final_timing.rpt').read_text(encoding='utf-8'))
    audit = json.loads((root / 'build/td/audit_summary.json').read_text(encoding='utf-8'))
    assert values == audit['timing_ns']
    for rel, expected in audit['input_sha256'].items():
        assert digest(root / rel) == expected, rel
    netlist = root / 'build/td/audit_physical_netlist.v'
    assert verify_phase_sampling(netlist) and verify_native_sdram_mapping(netlist)
    bits = [root / f for f in ('download/hx4s20c.bit', 'hx4s20c_Runs/phy_1/hx4s20c.bit',
                               'hx4s20c_Runs/best_result/hx4s20c.bit')]
    assert all(digest(p) == audit['bitstream_sha256'] for p in bits)
    for name in ('hx4s20c_pr.db', 'hx4s20c_phy.area'):
        primary = root / 'hx4s20c_Runs/phy_1' / name
        cached = root / 'hx4s20c_Runs/best_result' / name
        assert primary.is_file()
        if cached.is_file():
            assert digest(primary) == digest(cached)
    return {'status': 'PASS', 'verified_at_utc': datetime.now(timezone.utc).isoformat(),
            'timing_ns': values, 'bitstream_sha256': audit['bitstream_sha256'],
            'flow_sha256': digest(flow), 'board_validation': 'PENDING',
            'scope': 'Compact copy: current timing, native mapping, audited inputs and bitstream consistency',
            'functional_regression': 'Run functional test suites in the full source project after RTL edits.'}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check-only', type=Path)
    args = parser.parse_args()
    if args.check_only:
        verify(args.check_only.resolve())
        print('PASS read-only compact physical verifier')
        return
    for script in [('tools/build_td.py', 'audit'), ('tools/build_td.py', 'inspect'),
                   ('tools/test_phase_audit.py',), ('tools/test_native_audit.py',)]:
        subprocess.run([sys.executable, '-X', 'utf8', *script], cwd=ROOT, check=True)
    result = verify(ROOT)
    (ROOT / 'build/gui_holdfix_verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('PASS compact GUI build: timing, mapped native pads, phase sampling and three matching bitstreams')

if __name__ == '__main__':
    main()
