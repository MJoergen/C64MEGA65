# Minimal NMOS 6502 emulator for running the 1581 DOS ROM against device models.
# Documented opcodes only; decimal mode implemented for ADC/SBC.
class CPU:
    def __init__(self, read, write):
        self.read = read; self.write = write
        self.a=0; self.x=0; self.y=0; self.sp=0xFD; self.pc=0
        self.c=0; self.z=0; self.i=1; self.d=0; self.b=0; self.v=0; self.n=0
        self.cycles=0; self.irq_line=False
    def reset(self):
        self.pc = self.read(0xFFFC) | (self.read(0xFFFD)<<8); self.i=1
    def push(self,v): self.write(0x100+self.sp, v&0xFF); self.sp=(self.sp-1)&0xFF
    def pop(self): self.sp=(self.sp+1)&0xFF; return self.read(0x100+self.sp)
    def flags(self):
        return (self.n<<7)|(self.v<<6)|0x20|(self.b<<4)|(self.d<<3)|(self.i<<2)|(self.z<<1)|self.c
    def setflags(self,p):
        self.n=(p>>7)&1; self.v=(p>>6)&1; self.b=(p>>4)&1; self.d=(p>>3)&1
        self.i=(p>>2)&1; self.z=(p>>1)&1; self.c=p&1
    def nz(self,v): v&=0xFF; self.z=1 if v==0 else 0; self.n=(v>>7)&1; return v
    def fetch(self): v=self.read(self.pc); self.pc=(self.pc+1)&0xFFFF; return v
    def addr(self,mode):
        f=self.fetch
        if mode=='imm': a=self.pc; self.pc=(self.pc+1)&0xFFFF; return a
        if mode=='zp': return f()
        if mode=='zpx': return (f()+self.x)&0xFF
        if mode=='zpy': return (f()+self.y)&0xFF
        if mode=='abs': return f() | (f()<<8)
        if mode=='abx': return (f()|(f()<<8))+self.x & 0xFFFF
        if mode=='aby': return (f()|(f()<<8))+self.y & 0xFFFF
        if mode=='izx':
            z=(f()+self.x)&0xFF; return self.read(z)|(self.read((z+1)&0xFF)<<8)
        if mode=='izy':
            z=f(); return ((self.read(z)|(self.read((z+1)&0xFF)<<8))+self.y)&0xFFFF
        if mode=='ind':
            a=f()|(f()<<8); lo=self.read(a); hi=self.read((a&0xFF00)|((a+1)&0xFF)); return lo|(hi<<8)
        raise Exception(mode)
    def adc(self,v):
        if self.d:
            lo=(self.a&0x0F)+(v&0x0F)+self.c; hi=(self.a>>4)+(v>>4)
            if lo>9: lo+=6; hi+=1
            self.z=1 if ((self.a+v+self.c)&0xFF)==0 else 0
            self.n=(hi&0x08)>>3 if hi&0x8 else 0
            self.v=1 if (~(self.a^v)&(self.a^(hi<<4))&0x80) else 0
            if hi>9: hi+=6
            self.c=1 if hi>15 else 0
            self.a=((hi<<4)|(lo&0x0F))&0xFF
        else:
            r=self.a+v+self.c
            self.v=1 if (~(self.a^v)&(self.a^r)&0x80) else 0
            self.c=1 if r>0xFF else 0; self.a=self.nz(r)
    def sbc(self,v):
        if self.d:
            lo=(self.a&0x0F)-(v&0x0F)-(1-self.c); hi=(self.a>>4)-(v>>4)
            if lo&0x10: lo-=6; hi-=1
            r=self.a-v-(1-self.c)
            self.v=1 if ((self.a^v)&(self.a^r)&0x80) else 0
            self.c=0 if r<0 else 1; self.z=1 if (r&0xFF)==0 else 0; self.n=(r>>7)&1
            if hi&0x10: hi-=6
            self.a=((hi<<4)|(lo&0x0F))&0xFF
        else:
            r=self.a-v-(1-self.c)
            self.v=1 if ((self.a^v)&(self.a^r)&0x80) else 0
            self.c=0 if r<0 else 1; self.a=self.nz(r)
    def cmp_(self,r,v):
        d=r-v; self.c=1 if d>=0 else 0; self.nz(d)
    def branch(self,cond):
        off=self.fetch()
        if cond:
            if off>127: off-=256
            self.pc=(self.pc+off)&0xFFFF
    def irq(self):
        self.push(self.pc>>8); self.push(self.pc&0xFF)
        self.b=0; self.push(self.flags()); self.i=1
        self.pc=self.read(0xFFFE)|(self.read(0xFFFF)<<8)
    def step(self):
        if self.irq_line and not self.i:
            self.irq()
        op=self.fetch(); r=self.read; w=self.write
        def ld(m): return r(self.addr(m))
        if   op==0xA9: self.a=self.nz(ld('imm'))
        elif op==0xA5: self.a=self.nz(ld('zp'))
        elif op==0xB5: self.a=self.nz(ld('zpx'))
        elif op==0xAD: self.a=self.nz(ld('abs'))
        elif op==0xBD: self.a=self.nz(ld('abx'))
        elif op==0xB9: self.a=self.nz(ld('aby'))
        elif op==0xA1: self.a=self.nz(ld('izx'))
        elif op==0xB1: self.a=self.nz(ld('izy'))
        elif op==0xA2: self.x=self.nz(ld('imm'))
        elif op==0xA6: self.x=self.nz(ld('zp'))
        elif op==0xB6: self.x=self.nz(ld('zpy'))
        elif op==0xAE: self.x=self.nz(ld('abs'))
        elif op==0xBE: self.x=self.nz(ld('aby'))
        elif op==0xA0: self.y=self.nz(ld('imm'))
        elif op==0xA4: self.y=self.nz(ld('zp'))
        elif op==0xB4: self.y=self.nz(ld('zpx'))
        elif op==0xAC: self.y=self.nz(ld('abs'))
        elif op==0xBC: self.y=self.nz(ld('abx'))
        elif op==0x85: w(self.addr('zp'),self.a)
        elif op==0x95: w(self.addr('zpx'),self.a)
        elif op==0x8D: w(self.addr('abs'),self.a)
        elif op==0x9D: w(self.addr('abx'),self.a)
        elif op==0x99: w(self.addr('aby'),self.a)
        elif op==0x81: w(self.addr('izx'),self.a)
        elif op==0x91: w(self.addr('izy'),self.a)
        elif op==0x86: w(self.addr('zp'),self.x)
        elif op==0x96: w(self.addr('zpy'),self.x)
        elif op==0x8E: w(self.addr('abs'),self.x)
        elif op==0x84: w(self.addr('zp'),self.y)
        elif op==0x94: w(self.addr('zpx'),self.y)
        elif op==0x8C: w(self.addr('abs'),self.y)
        elif op==0xAA: self.x=self.nz(self.a)
        elif op==0xA8: self.y=self.nz(self.a)
        elif op==0x8A: self.a=self.nz(self.x)
        elif op==0x98: self.a=self.nz(self.y)
        elif op==0xBA: self.x=self.nz(self.sp)
        elif op==0x9A: self.sp=self.x
        elif op==0x69: self.adc(ld('imm'))
        elif op==0x65: self.adc(ld('zp'))
        elif op==0x75: self.adc(ld('zpx'))
        elif op==0x6D: self.adc(ld('abs'))
        elif op==0x7D: self.adc(ld('abx'))
        elif op==0x79: self.adc(ld('aby'))
        elif op==0x61: self.adc(ld('izx'))
        elif op==0x71: self.adc(ld('izy'))
        elif op==0xE9: self.sbc(ld('imm'))
        elif op==0xE5: self.sbc(ld('zp'))
        elif op==0xF5: self.sbc(ld('zpx'))
        elif op==0xED: self.sbc(ld('abs'))
        elif op==0xFD: self.sbc(ld('abx'))
        elif op==0xF9: self.sbc(ld('aby'))
        elif op==0xE1: self.sbc(ld('izx'))
        elif op==0xF1: self.sbc(ld('izy'))
        elif op==0xC9: self.cmp_(self.a,ld('imm'))
        elif op==0xC5: self.cmp_(self.a,ld('zp'))
        elif op==0xD5: self.cmp_(self.a,ld('zpx'))
        elif op==0xCD: self.cmp_(self.a,ld('abs'))
        elif op==0xDD: self.cmp_(self.a,ld('abx'))
        elif op==0xD9: self.cmp_(self.a,ld('aby'))
        elif op==0xC1: self.cmp_(self.a,ld('izx'))
        elif op==0xD1: self.cmp_(self.a,ld('izy'))
        elif op==0xE0: self.cmp_(self.x,ld('imm'))
        elif op==0xE4: self.cmp_(self.x,ld('zp'))
        elif op==0xEC: self.cmp_(self.x,ld('abs'))
        elif op==0xC0: self.cmp_(self.y,ld('imm'))
        elif op==0xC4: self.cmp_(self.y,ld('zp'))
        elif op==0xCC: self.cmp_(self.y,ld('abs'))
        elif op==0x29: self.a=self.nz(self.a&ld('imm'))
        elif op==0x25: self.a=self.nz(self.a&ld('zp'))
        elif op==0x35: self.a=self.nz(self.a&ld('zpx'))
        elif op==0x2D: self.a=self.nz(self.a&ld('abs'))
        elif op==0x3D: self.a=self.nz(self.a&ld('abx'))
        elif op==0x39: self.a=self.nz(self.a&ld('aby'))
        elif op==0x21: self.a=self.nz(self.a&ld('izx'))
        elif op==0x31: self.a=self.nz(self.a&ld('izy'))
        elif op==0x09: self.a=self.nz(self.a|ld('imm'))
        elif op==0x05: self.a=self.nz(self.a|ld('zp'))
        elif op==0x15: self.a=self.nz(self.a|ld('zpx'))
        elif op==0x0D: self.a=self.nz(self.a|ld('abs'))
        elif op==0x1D: self.a=self.nz(self.a|ld('abx'))
        elif op==0x19: self.a=self.nz(self.a|ld('aby'))
        elif op==0x01: self.a=self.nz(self.a|ld('izx'))
        elif op==0x11: self.a=self.nz(self.a|ld('izy'))
        elif op==0x49: self.a=self.nz(self.a^ld('imm'))
        elif op==0x45: self.a=self.nz(self.a^ld('zp'))
        elif op==0x55: self.a=self.nz(self.a^ld('zpx'))
        elif op==0x4D: self.a=self.nz(self.a^ld('abs'))
        elif op==0x5D: self.a=self.nz(self.a^ld('abx'))
        elif op==0x59: self.a=self.nz(self.a^ld('aby'))
        elif op==0x41: self.a=self.nz(self.a^ld('izx'))
        elif op==0x51: self.a=self.nz(self.a^ld('izy'))
        elif op==0x24: v=ld('zp'); self.z=1 if (self.a&v)==0 else 0; self.n=(v>>7)&1; self.v=(v>>6)&1
        elif op==0x2C: v=ld('abs'); self.z=1 if (self.a&v)==0 else 0; self.n=(v>>7)&1; self.v=(v>>6)&1
        elif op in (0x0A,0x06,0x16,0x0E,0x1E):  # ASL
            if op==0x0A: self.c=(self.a>>7)&1; self.a=self.nz((self.a<<1)&0xFF)
            else:
                m={'0x06':'zp'}; mode={0x06:'zp',0x16:'zpx',0x0E:'abs',0x1E:'abx'}[op]
                a=self.addr(mode); v=r(a); self.c=(v>>7)&1; v=self.nz((v<<1)&0xFF); w(a,v)
        elif op in (0x4A,0x46,0x56,0x4E,0x5E):  # LSR
            if op==0x4A: self.c=self.a&1; self.a=self.nz(self.a>>1)
            else:
                mode={0x46:'zp',0x56:'zpx',0x4E:'abs',0x5E:'abx'}[op]
                a=self.addr(mode); v=r(a); self.c=v&1; v=self.nz(v>>1); w(a,v)
        elif op in (0x2A,0x26,0x36,0x2E,0x3E):  # ROL
            if op==0x2A: c=self.c; self.c=(self.a>>7)&1; self.a=self.nz(((self.a<<1)|c)&0xFF)
            else:
                mode={0x26:'zp',0x36:'zpx',0x2E:'abs',0x3E:'abx'}[op]
                a=self.addr(mode); v=r(a); c=self.c; self.c=(v>>7)&1; v=self.nz(((v<<1)|c)&0xFF); w(a,v)
        elif op in (0x6A,0x66,0x76,0x6E,0x7E):  # ROR
            if op==0x6A: c=self.c; self.c=self.a&1; self.a=self.nz((self.a>>1)|(c<<7))
            else:
                mode={0x66:'zp',0x76:'zpx',0x6E:'abs',0x7E:'abx'}[op]
                a=self.addr(mode); v=r(a); c=self.c; self.c=v&1; v=self.nz((v>>1)|(c<<7)); w(a,v)
        elif op==0xE6: a=self.addr('zp'); w(a,self.nz(r(a)+1))
        elif op==0xF6: a=self.addr('zpx'); w(a,self.nz(r(a)+1))
        elif op==0xEE: a=self.addr('abs'); w(a,self.nz(r(a)+1))
        elif op==0xFE: a=self.addr('abx'); w(a,self.nz(r(a)+1))
        elif op==0xC6: a=self.addr('zp'); w(a,self.nz(r(a)-1))
        elif op==0xD6: a=self.addr('zpx'); w(a,self.nz(r(a)-1))
        elif op==0xCE: a=self.addr('abs'); w(a,self.nz(r(a)-1))
        elif op==0xDE: a=self.addr('abx'); w(a,self.nz(r(a)-1))
        elif op==0xE8: self.x=self.nz(self.x+1)
        elif op==0xC8: self.y=self.nz(self.y+1)
        elif op==0xCA: self.x=self.nz(self.x-1)
        elif op==0x88: self.y=self.nz(self.y-1)
        elif op==0x4C: self.pc=self.addr('abs')
        elif op==0x6C: self.pc=self.addr('ind')
        elif op==0x20:
            a=self.addr('abs'); ret=(self.pc-1)&0xFFFF
            self.push(ret>>8); self.push(ret&0xFF); self.pc=a
        elif op==0x60: self.pc=((self.pop()|(self.pop()<<8))+1)&0xFFFF
        elif op==0x40: self.setflags(self.pop()); self.pc=self.pop()|(self.pop()<<8)
        elif op==0x00:
            self.pc=(self.pc+1)&0xFFFF
            self.push(self.pc>>8); self.push(self.pc&0xFF)
            self.b=1; self.push(self.flags()); self.i=1
            self.pc=r(0xFFFE)|(r(0xFFFF)<<8)
        elif op==0x10: self.branch(self.n==0)
        elif op==0x30: self.branch(self.n==1)
        elif op==0x50: self.branch(self.v==0)
        elif op==0x70: self.branch(self.v==1)
        elif op==0x90: self.branch(self.c==0)
        elif op==0xB0: self.branch(self.c==1)
        elif op==0xD0: self.branch(self.z==0)
        elif op==0xF0: self.branch(self.z==1)
        elif op==0x18: self.c=0
        elif op==0x38: self.c=1
        elif op==0x58: self.i=0
        elif op==0x78: self.i=1
        elif op==0xB8: self.v=0
        elif op==0xD8: self.d=0
        elif op==0xF8: self.d=1
        elif op==0x48: self.push(self.a)
        elif op==0x68: self.a=self.nz(self.pop())
        elif op==0x08: self.b=1; self.push(self.flags())
        elif op==0x28: self.setflags(self.pop())
        elif op==0xEA: pass
        else:
            raise Exception(f"opcode ${op:02X} at ${(self.pc-1)&0xFFFF:04X}")
        self.cycles+=3  # coarse average; devices use cycle counts loosely
