"""Restore the project-local GUI physical script and its saved selection."""
from pathlib import Path
import re,shutil
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=ROOT/'hx4s20c.al';data=p.read_text(encoding='utf-8')
    def select(m):
        tag=re.sub(r'\suseDefaultScript="[^"]*"','',m[0])
        return tag[:-1]+' useDefaultScript="false">'
    data,n=re.subn(r'<Run\b[^>]*Name="phy_1"[^>]*>',select,data)
    assert n==1
    p.write_text(data,encoding='utf-8')
    target=ROOT/'hx4s20c_Runs/phy_1/hx4s20c.tcl';target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'td/gui_phy_flow.tcl',target)
    print('PASS GUI custom physical flow installed; reload the project if TD is open')
if __name__=='__main__':main()
