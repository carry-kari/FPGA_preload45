"""Build the local EG4 project with absolute, forward-slash TD paths."""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def verify_phase_sampling(netlist):
    """Allow the sole pixel-clock data sink in the serial phase sampler.

    LocalWireNum counts route resources; a single data sink can use two.
    Validate the exported routed connections in addition to fanout counts.
    """
    source = re.sub(r"//[^\n]*|/\*.*?\*/", "", netlist.read_text(errors="replace"), flags=re.S)
    data_ports = []
    for port in re.finditer(r"\.(\w+)\s*\(([^()]*)\)", source):
        if not re.search(r"\bpix_clk\b", port[2]):
            continue
        if "clk" in port[1].lower():
            continue
        data_ports.append(port)
    if (len(data_ports) != 1 or data_ports[0][1] != "mi" or
            len(re.findall(r"\bpix_clk\b", data_ports[0][2])) != 1):
        return False
    # REGn_SD=MI maps mi[n] directly to q[n] in EG4 MSLICE/LSLICE registers.
    # Trace both stages by lane, including placements in separate slices.
    cells = []
    for cell in re.finditer(r"(EG_PHY_\w+)\s*#\((.*?)\)\s*(\\\S+|\w+)\s*\((.*?)\);", source, re.S):
        attributes = dict(re.findall(r'\.(\w+)\("([^"\n]*)"\)', cell[2]))
        ports = dict(re.findall(r"\.(\w+)\s*\(([^()]*)\)", cell[4]))
        cells.append((cell[1], attributes, ports))

    def vector(value):
        value = value.strip()
        return [bit.strip() for bit in value[1:-1].split(",")] if value.startswith("{") and value.endswith("}") else [value]

    def stage(output, data):
        drivers = [(kind, attributes, ports) for kind, attributes, ports in cells
                   if output in vector(ports.get("q", ""))]
        if len(drivers) != 1:
            return False
        kind, attributes, ports = drivers[0]
        q, mi = vector(ports.get("q", "")), vector(ports.get("mi", ""))
        if kind not in ("EG_PHY_MSLICE", "EG_PHY_LSLICE") or len(q) != 2 or len(mi) != 2 or q.count(output) != 1:
            return False
        index = q.index(output)
        lane = 1 - index
        return (mi[index] == data and ports.get("clk", "").strip() == r"\serial/clk_5x" and
                attributes.get("DFFMODE") == "FF" and attributes.get("CLKMUX") == "CLK" and
                attributes.get("CEMUX") == "1" and attributes.get(f"REG{lane}_SD") == "MI")

    return stage(r"\serial/pix_meta", "pix_clk") and stage(r"\serial/pix_sync", r"\serial/pix_meta")


def verify_native_sdram_mapping(netlist):
    """Verify the single hard SDRAM and every reserved SIP pad, including CLK S73."""
    source = netlist.read_text(errors="replace")
    macros = re.findall(r"EG_PHY_SDRAM_2M_32\s+\\player/image_ram/memory\s*\((.*?)\);", source, re.S)
    pll = re.search(r"EG_PHY_PLL\s*#\((.*?)\)\s*\\u_pll/pll\s*\((.*?)\);",source,re.S)
    if not pll:
        return False
    for parameter,value in (("CLKC2_DIV",15),("CLKC3_DIV",15),
                            ("CLKC2_CPHASE",1),("CLKC3_CPHASE",8),
                            ("REFCLK_DIV",5),("FBCLK_DIV",63)):
        if re.search(r"\."+parameter+r"\("+str(value)+r"\)",pll[1]) is None:
            return False
    if re.search(r"\.clkc\(\{[^,]+,\\player/image_ram/sd_clk\s*,\\player/image_ram/controller/clk\s*,",pll[2]) is None:
        return False
    if len(macros) != 1 or not re.search(r"\.clk\(clk\)", macros[0]):
        return False
    if set(map(int, re.findall(r"\\dq\[(\d+)\]", macros[0]))) != set(range(32)):
        return False
    expected = {f"dq[{i}]": f"S{p}" for i, p in enumerate(
        (1,2,5,6,7,8,11,12,78,79,82,83,84,85,88,89,
         42,41,38,37,36,35,32,31,59,58,55,54,53,52,49,48))}
    expected.update({f"addr[{i}]": f"S{p}" for i,p in enumerate((67,66,65,64,28,27,26,25,24,23,68))})
    expected.update({"ba[0]":"S69","ba[1]":"S70","cke":"S18","we_n":"S19",
                     "cas_n":"S20","ras_n":"S21","cs_n":"S22","clk":"S73",
                     "dm0":"S14","dm1":"S76","dm2":"S29","dm3":"S61"})
    pads = re.findall(r"EG_PHY_PAD\s*#\((.*?)\)\s*(\\\S+|\w+)\s*\((.*?)\);",source,re.S)
    actual = {}
    clock_pad_ok = False
    for attributes,name,ports in pads:
        if not name.startswith(r"\player/image_ram/memory_syn_"):
            continue
        info = re.search(r'\.SIP_INFO\("([^"/]+)/([^"/]+)"\)', attributes)
        location = re.search(r'\.LOCATION\("([^"/]+)"\)',attributes)
        if not info or not location or info[2] != location[1] or info[1] in actual:
            return False
        actual[info[1]] = location[1]
        if info[1] == "clk":
            clock_pad_ok = (re.search(r"\.opad\(clk\)",ports) is not None and
                            re.search(r"\.do\([^()]*\\player/image_ram/sd_clk\s*\}\)",ports) is not None)
    data_sinks = [p[1] for p in re.finditer(r"\.(\w+)\s*\(([^()]*)\)",source)
                  if re.search(r"\\player/image_ram/sd_clk\s",p[2]) and "clk" not in p[1].lower()]
    return actual == expected and clock_pad_ok and data_sinks == ["do"]


def save_audit(report, minimum_hold_slack):
    values = {}
    for label in ("SWNS", "HWNS", "STNS", "HTNS"):
        match = re.search(label+r":\s+(-?[\d.]+)ns", report)
        if not match:
            raise SystemExit(f"Missing timing result: {label}")
        values[label] = float(match[1])
    paths = []
    pattern = (r"Slack\s+:\s+(-?[\d.]+)ns\s*\n"
               r"Begin Point\s+:\s+([^\n]+)\n"
               r"End Point\s+:\s+([^\n]+)\n"
               r"Check Type\s+:\s+(\w+)\s*\nProcess\s+:\s+(\w+)")
    for match in re.finditer(pattern, report):
        paths.append({"slack_ns": float(match[1]), "begin": match[2].strip(),
                      "end": match[3].strip(), "check": match[4], "corner": match[5]})
    min_paths = [p for p in paths if p["check"] in ("hold", "removal")]
    if not min_paths:
        raise SystemExit("Missing detailed hold/removal paths")
    bitstream = ROOT/"hx4s20c_Runs/best_result/hx4s20c.bit"
    inputs = sorted([*(ROOT/"rtl").glob("*.v"), *(ROOT/"constraints").glob("*"),
                     *(ROOT/"vendor_ip").glob("*.v"),*(ROOT/"td").glob("*.tcl"),
                     ROOT/"hx4s20c.al",ROOT/"tools/build_td.py"])
    summary = {"audited_at_utc": datetime.now(timezone.utc).isoformat(),
               "timing_ns": values, "minimum_hold_slack_ns": minimum_hold_slack,
               "worst_min_path": min(min_paths, key=lambda p:p["slack_ns"]),
               "input_sha256": {p.relative_to(ROOT).as_posix():
                                hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in inputs if p.is_file()},
               "bitstream_sha256": hashlib.sha256(bitstream.read_bytes()).hexdigest()
                                       if bitstream.exists() else None}
    target = ROOT/"build/td/audit_summary.json"
    target.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"TIMING setup={values['SWNS']:.3f} ns hold/removal={values['HWNS']:.3f} ns", flush=True)
    print(f"AUDIT {target}", flush=True)
    if values["SWNS"] < 0 or values["HWNS"] < minimum_hold_slack:
        raise SystemExit(f"Timing failed: required hold/removal >= {minimum_hold_slack:.3f} ns")
    if values["STNS"] < 0 or values["HTNS"] < 0:
        raise SystemExit("Timing failed: nonzero negative slack total")
    if values["HWNS"] < 0.100:
        print("REVIEW hold/removal margin below 0.100 ns; retain checks and verify on board", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("syn", "physical", "holdfix", "audit", "inspect", "all"), default="all", nargs="?")
    parser.add_argument("--td", type=Path, default=Path(os.environ.get("TD_EXE", "D:/AnLU/bin/td_commands_prompt.exe")))
    parser.add_argument("--min-hold-slack", type=float, default=0.0,
                        help="required hold/removal margin in ns (default: 0; review below 0.100)")
    args = parser.parse_args()
    if not 0 <= args.min_hold_slack < float("inf"):
        parser.error("--min-hold-slack must be finite and nonnegative")
    out = ROOT / "build" / "td"
    out.mkdir(parents=True, exist_ok=True)
    project = ROOT / "hx4s20c.al"
    stages = {"syn": ["init", "build"], "physical": ["init", "physical", "holdfix", "audit"],
              "holdfix": ["holdfix", "audit"],
              "audit": ["audit"], "inspect": ["inspect_routing", "inspect_clocks"],
              "all": ["init", "build", "physical", "holdfix", "audit"]}[args.stage]
    for stage in stages:
        source = (ROOT / "td" / f"{stage}.tcl").read_text()
        source = source.replace("@ROOT@", ROOT.as_posix())
        if stage == "init" and project.exists():
            source = re.sub(r"create_project.*", "open_project {"+project.as_posix()+"}", source)
        script = out / f"{stage}.tcl"
        script.write_text(source, encoding="utf-8")
        result = subprocess.run([str(args.td), script.as_posix()],
                                cwd=project.parent if project.exists() else ROOT,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = result.stdout.decode("utf-8", errors="replace")
        (out / f"{stage}.log").write_text(log, encoding="utf-8")
        print(f"TD {stage}: {out / (stage + '.log')}", flush=True)
        failures = re.findall(r"^.*(?:ERROR:|FATAL:|CRITICAL-WARNING:).*$", log, re.MULTILINE)
        if stage=="holdfix":
            routed=out/'holdfix_physical_netlist.v'
            native_ok=routed.exists() and verify_native_sdram_mapping(routed)
            phase_ok=routed.exists() and verify_phase_sampling(routed)
            local=re.search(r"pix_clk\s*\|\s*AL_PHY_PLL\s*\|\s*(\d+)/(\d+)\s*\|\s*(\d+)\s*\|\s*pix_clk",log)
            forwarded=re.search(r"sdram_clk\s*\|\s*AL_PHY_PLL\s*\|\s*0/1\s*\|\s*1\s*\|\s*player/image_ram/sd_clk",log)
            if native_ok and phase_ok and local and int(local[2])==int(local[1])+1 and int(local[3])>=1 and forwarded:
                failures=[line for line in failures if not ('PHY-5079' in line and 'Marked 2 clock net(s)' in line)]
                print('REVIEW ECO PHY-5079: sole serial phase input and S73 SDRAM clock output reverified',flush=True)
        if result.returncode or failures:
            raise SystemExit("\n".join(failures) or f"TD exited {result.returncode}")
    if "audit" in stages:
        report = (ROOT/"hx4s20c_Runs/phy_1/final_timing.rpt").read_text()
        for clock, frequency in (("clk_50m", r"50\.000"), ("pix_clk", r"25\.200"),
                                 ("serial_clk_5x", r"126\.\d+"),
                                 ("mem_clk",r"42\.\d+"),("sdram_clk",r"42\.\d+")):
            if not re.search(r"clk\d+:\s+"+frequency+r"\s+\d+\s+"+clock+r"\b", report):
                raise SystemExit(f"Missing PLL timing clock: {clock}")
        if "pix_clk -> serial_clk_5x" not in report:
            raise SystemExit("Serializer clock crossing absent from timing audit")
        for crossing in ("pix_clk -> mem_clk", "mem_clk -> pix_clk",
                         "mem_clk -> sdram_clk", "sdram_clk -> mem_clk"):
            if crossing not in report:
                raise SystemExit(f"Native memory crossing absent: {crossing}")
        save_audit(report, args.min_hold_slack)
    runs = ("syn_1",) if args.stage == "syn" else ("syn_1", "phy_1")
    for run in runs:
        folder = ROOT/"hx4s20c_Runs"/run
        warnings = (folder/"run.logw").read_text(errors="replace")
        for line in warnings.splitlines():
            if "ERROR:" in line or "FATAL:" in line:
                raise SystemExit(line)
            if "SYN-5011" in line and 'pin "clk"' in line and "rtl/" in line:
                raise SystemExit(line)
            if "CRITICAL-WARNING:" in line:
                routing = (folder/"run.log").read_text(errors="replace")
                netlist = ROOT/"build/td/audit_physical_netlist.v"
                native_ok = netlist.exists() and verify_native_sdram_mapping(netlist)
                if ("PHY-7002" in line and "Instance player/image_ram/memory location" in line
                        and native_ok and not re.search(r"memory.*LOCATION",(ROOT/"constraints/hx4s20c.adc").read_text(),re.I)):
                    print("REVIEW PHY-7002: virtual hard-SDRAM placement was relocated by TD; all 55 reserved SIP pads verified",flush=True)
                    continue
                known = "PHY-5079" in line and re.search(
                    r"pix_clk\s*\|\s*AL_PHY_PLL\s*\|\s*(\d+)/(\d+)\s*\|\s*(\d+)\s*\|\s*pix_clk", routing)
                if (not known or int(known[2]) != int(known[1])+1 or
                    int(known[3]) < 1 or not netlist.exists() or not verify_phase_sampling(netlist)):
                    raise SystemExit(line)
                forwarded = re.search(r"sdram_clk\s*\|\s*AL_PHY_PLL\s*\|\s*0/1\s*\|\s*1\s*\|\s*player/image_ram/sd_clk",routing)
                marked = re.search(r"Marked (\d+) clock net",line)
                if marked and (int(marked[1]) != 2 or not forwarded or not native_ok):
                    raise SystemExit("Unverified clock routing exception: "+line)
                print(f"REVIEW PHY-5079: {known[3]} local route resources, one verified serializer phase-data sink; other clock exceptions remain blocked", flush=True)
                print("REVIEW PHY-5079: second route is the sole SDRAM clock output pad S73; no fabric data sinks",flush=True)
    print("PASS TD build", flush=True)


if __name__ == "__main__":
    main()
