"""Streaming proof that removing signed declarations preserves structural bits.

Accept only declarations, direct net assignments and named-pin structural cells.
Forbid expressions with arithmetic/operators. Check every width adjustment: no
widening may depend on a signed declaration that is being removed. Output-port
widening is checked in the reverse direction. Thus changing these declarations
cannot alter a cell input, an assignment, or a hierarchical output connection.
"""
import json,re
from pathlib import Path
from scripts.t01_resume_common import WORK,save,sha,run_logged
IDENT=r'(?:\\[^\s]+|[A-Za-z_$][A-Za-z0-9_$]*)'
ID=re.compile(IDENT)
DECL=re.compile(r'^(input|output|inout|wire)\s+(signed\s+)?(?:\[(\d+):(\d+)\]\s+)?('+IDENT+r')\s*;$')
def canonical(s):return s[1:] if s.startswith('\\') else s
def declaration(s):
    m=DECL.fullmatch(s);assert m,('Unsupported declaration',s[:200])
    high,low=(int(m[3]),int(m[4])) if m[3] else (0,0)
    return canonical(m[5]),dict(direction=m[1],signed=bool(m[2]),width=abs(high-low)+1,high=max(high,low),low=min(high,low))
def interfaces(raw,lib,yosys,folder):
    cache=WORK/'lib_interfaces'/sha(lib)[:16];cache.mkdir(parents=True,exist_ok=True)
    jsonpath=cache/'ports.json'
    if not jsonpath.exists():
        script=cache/'ports.ys';script.write_text(f'read_liberty -lib "{lib}"\nwrite_json "{jsonpath}"\n')
        run_logged([str(yosys),'-q','-s',str(script)],folder/'sta_lib_interfaces.log')
    d=json.loads(jsonpath.read_text());modules={}
    for name,m in d['modules'].items():
        modules[canonical(name)]={k:dict(direction=v['direction'],width=len(v['bits']),signed=bool(v.get('signed',False))) for k,v in m['ports'].items()}
    own={};module=None;header=False
    with raw.open() as f:
        for line in f:
            s=line.strip()
            if s.startswith('module '):
                m=ID.match(s,7);assert m;sname=canonical(m[0]);assert sname not in own
                own[sname]={};module=sname;header=';' not in s;continue
            if header:
                header=';' not in s;continue
            if s=='endmodule':module=None;continue
            if re.match(r'^(input|output|inout)\s',s):
                assert module;name,v=declaration(s);own[module][name]=v
    assert not module and not header
    assert not set(own)&set(modules),'Library/user module name collision'
    modules.update(own);return modules,set(own)

class Expression:
    def __init__(self,text,wires):self.s=text;self.i=0;self.wires=wires
    def space(self):
        while self.i<len(self.s) and self.s[self.i].isspace():self.i+=1
    def parse(self):
        self.space();assert self.i<len(self.s)
        if self.s[self.i]=='{':
            self.i+=1;self.space()
            repeat=re.match(r'(\d+)\s*\{',self.s[self.i:])
            if repeat:
                n=int(repeat[1]);self.i+=repeat.end()-1;w,_=self.parse();self.space();assert self.s[self.i]=='}';self.i+=1;return n*w,False
            width=0
            while True:
                w,_=self.parse();width+=w;self.space()
                if self.s[self.i]=='}':self.i+=1;break
                assert self.s[self.i]==',';self.i+=1
            return width,False
        lit=re.match(r"(\d+)'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+",self.s[self.i:])
        if lit:self.i+=lit.end();return int(lit[1]),False
        ident=ID.match(self.s,self.i);assert ident,('Not a structural signal expression',self.s[self.i:self.i+120])
        self.i=ident.end();name=canonical(ident[0]);assert name in self.wires,('Undeclared wire',name)
        v=self.wires[name];self.space()
        if self.i<len(self.s) and self.s[self.i]=='[':
            sel=re.match(r'\[(\d+)(?::(\d+))?\]',self.s[self.i:]);assert sel
            a=int(sel[1]);b=int(sel[2]) if sel[2] else a
            assert v['low']<=a<=v['high'] and v['low']<=b<=v['high'],('Out-of-range select',name,sel[0],v)
            self.i+=sel.end();return abs(a-b)+1,False
        return v['width'],v['signed']
    def complete(self):
        result=self.parse();self.space();assert self.i==len(self.s),('Operators/extra syntax forbidden',self.s[self.i:]);return result

def prove(raw,lib,yosys):
    raw=Path(raw);modules,own=interfaces(raw,Path(lib),yosys,raw.parent)
    counts=dict(modules=0,wires=0,cells=0,pin_connections=0,assignments=0,open_connections=0,safe_width_adjustments=0)
    module=None;wires={};header=False;celltype=None;seenpins=set();instance=None
    def assignment_safe(target_width,source_width,sensitive,where):
        assert not (target_width>source_width and sensitive),('Signed-dependent extension',where,target_width,source_width)
        if target_width!=source_width:counts['safe_width_adjustments']+=1
    with raw.open() as f:
        for lineno,line in enumerate(f,1):
            s=line.strip()
            if not s or s.startswith(('/*','//')):continue
            if s.startswith('module '):
                assert module is None;module=canonical(ID.match(s,7)[0]);counts['modules']+=1;wires={};header=';' not in s;continue
            if header:header=';' not in s;continue
            if s=='endmodule':
                assert module and celltype is None;module=None;wires={};continue
            assert module,('Unexpected top-level syntax',lineno,s[:100])
            if celltype:
                if s==');':celltype=None;continue
                assert s.startswith('.'),('Positional/unsupported port syntax',lineno,s[:120])
                m=ID.match(s,1);assert m;pin=canonical(m[0]);tail=s[m.end():].strip()
                assert tail.startswith('(') and tail.rstrip(',').endswith(')'),(lineno,s[:100])
                expr=tail.rstrip(',')[1:-1].strip();assert pin in modules[celltype] and pin not in seenpins,(celltype,pin)
                seenpins.add(pin);counts['pin_connections']+=1
                if not expr:counts['open_connections']+=1;continue
                width,sensitive=Expression(expr,wires).complete();port=modules[celltype][pin]
                if port['direction']=='input':assignment_safe(port['width'],width,sensitive,(module,instance,pin,lineno))
                elif port['direction']=='output':assignment_safe(width,port['width'],port['signed'],(module,instance,pin,lineno))
                else:assert width==port['width'],('inout width mismatch',lineno)
                continue
            if re.match(r'^(input|output|inout|wire)\s',s):
                name,v=declaration(s)
                if name in wires:assert all(wires[name][k]==v[k] for k in ['width','signed','high','low']),(module,name)
                else:counts['wires']+=1
                wires[name]=v;continue
            if s.startswith('assign '):
                assert s.endswith(';') and s.count(' = ')==1,(lineno,s[:100])
                lhs,rhs=s[7:-1].split(' = ');lw,_=Expression(lhs,wires).complete();rw,sensitive=Expression(rhs,wires).complete()
                assignment_safe(lw,rw,sensitive,(module,'assign',lineno));counts['assignments']+=1;continue
            a=ID.match(s);assert a,('Unsupported body syntax',lineno,s[:120]);ctype=canonical(a[0]);tail=s[a.end():].lstrip()
            b=ID.match(tail);assert b and tail[b.end():].strip()=='(',('Unsupported cell declaration',lineno,s[:120])
            assert ctype in modules,('Unknown cell type',ctype,lineno)
            celltype=ctype;instance=canonical(b[0]);seenpins=set();counts['cells']+=1
    assert module is None and celltype is None and counts['modules']==len(own)
    return dict(status='PASS_STRUCTURAL_SIGNEDNESS_INDEPENDENCE',counts=counts,input_sha256=sha(raw),liberty_sha256=sha(lib),checker_sha256=sha(Path(__file__)),
      rule='Only structural signal expressions allowed; every assignment and named cell port checked. No widening depends on a removed signed wire/input/output declaration. Explicit constants, slices and concatenations retain their signedness. All non-declaration text is preserved byte-for-byte by the adapter.')
