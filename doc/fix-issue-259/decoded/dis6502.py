#!/usr/bin/env python3
"""Minimal 6502 disassembler: dis6502.py <file> <file_offset> <org> <length> [labels...]"""
import sys
OPS = {}
def add(mn, modes):
    for op, m in modes.items(): OPS[op] = (mn, m)
# mode: imp, acc, imm, zp, zpx, zpy, abs, abx, aby, ind, inx, iny, rel
add('ADC',{0x69:'imm',0x65:'zp',0x75:'zpx',0x6d:'abs',0x7d:'abx',0x79:'aby',0x61:'inx',0x71:'iny'})
add('AND',{0x29:'imm',0x25:'zp',0x35:'zpx',0x2d:'abs',0x3d:'abx',0x39:'aby',0x21:'inx',0x31:'iny'})
add('ASL',{0x0a:'acc',0x06:'zp',0x16:'zpx',0x0e:'abs',0x1e:'abx'})
add('BCC',{0x90:'rel'});add('BCS',{0xb0:'rel'});add('BEQ',{0xf0:'rel'});add('BMI',{0x30:'rel'})
add('BNE',{0xd0:'rel'});add('BPL',{0x10:'rel'});add('BVC',{0x50:'rel'});add('BVS',{0x70:'rel'})
add('BIT',{0x24:'zp',0x2c:'abs'});add('BRK',{0x00:'imp'})
add('CLC',{0x18:'imp'});add('CLD',{0xd8:'imp'});add('CLI',{0x58:'imp'});add('CLV',{0xb8:'imp'})
add('CMP',{0xc9:'imm',0xc5:'zp',0xd5:'zpx',0xcd:'abs',0xdd:'abx',0xd9:'aby',0xc1:'inx',0xd1:'iny'})
add('CPX',{0xe0:'imm',0xe4:'zp',0xec:'abs'});add('CPY',{0xc0:'imm',0xc4:'zp',0xcc:'abs'})
add('DEC',{0xc6:'zp',0xd6:'zpx',0xce:'abs',0xde:'abx'});add('DEX',{0xca:'imp'});add('DEY',{0x88:'imp'})
add('EOR',{0x49:'imm',0x45:'zp',0x55:'zpx',0x4d:'abs',0x5d:'abx',0x59:'aby',0x41:'inx',0x51:'iny'})
add('INC',{0xe6:'zp',0xf6:'zpx',0xee:'abs',0xfe:'abx'});add('INX',{0xe8:'imp'});add('INY',{0xc8:'imp'})
add('JMP',{0x4c:'abs',0x6c:'ind'});add('JSR',{0x20:'abs'})
add('LDA',{0xa9:'imm',0xa5:'zp',0xb5:'zpx',0xad:'abs',0xbd:'abx',0xb9:'aby',0xa1:'inx',0xb1:'iny'})
add('LDX',{0xa2:'imm',0xa6:'zp',0xb6:'zpy',0xae:'abs',0xbe:'aby'})
add('LDY',{0xa0:'imm',0xa4:'zp',0xb4:'zpx',0xac:'abs',0xbc:'abx'})
add('LSR',{0x4a:'acc',0x46:'zp',0x56:'zpx',0x4e:'abs',0x5e:'abx'});add('NOP',{0xea:'imp'})
add('ORA',{0x09:'imm',0x05:'zp',0x15:'zpx',0x0d:'abs',0x1d:'abx',0x19:'aby',0x01:'inx',0x11:'iny'})
add('PHA',{0x48:'imp'});add('PHP',{0x08:'imp'});add('PLA',{0x68:'imp'});add('PLP',{0x28:'imp'})
add('ROL',{0x2a:'acc',0x26:'zp',0x36:'zpx',0x2e:'abs',0x3e:'abx'})
add('ROR',{0x6a:'acc',0x66:'zp',0x76:'zpx',0x6e:'abs',0x7e:'abx'})
add('RTI',{0x40:'imp'});add('RTS',{0x60:'imp'})
add('SBC',{0xe9:'imm',0xe5:'zp',0xf5:'zpx',0xed:'abs',0xfd:'abx',0xf9:'aby',0xe1:'inx',0xf1:'iny'})
add('SEC',{0x38:'imp'});add('SED',{0xf8:'imp'});add('SEI',{0x78:'imp'})
add('STA',{0x85:'zp',0x95:'zpx',0x8d:'abs',0x9d:'abx',0x99:'aby',0x81:'inx',0x91:'iny'})
add('STX',{0x86:'zp',0x96:'zpy',0x8e:'abs'});add('STY',{0x84:'zp',0x94:'zpx',0x8c:'abs'})
add('TAX',{0xaa:'imp'});add('TAY',{0xa8:'imp'});add('TSX',{0xba:'imp'});add('TXA',{0x8a:'imp'})
add('TXS',{0x9a:'imp'});add('TYA',{0x98:'imp'})
LEN = {'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'abs':3,'abx':3,'aby':3,'ind':3,'inx':2,'iny':2,'rel':2}
REU = {0xdf00:'REU_STATUS',0xdf01:'REU_CMD',0xdf02:'REU_C64L',0xdf03:'REU_C64H',0xdf04:'REU_REUL',0xdf05:'REU_REUH',0xdf06:'REU_BANK',0xdf07:'REU_LENL',0xdf08:'REU_LENH',0xdf09:'REU_IRQMASK',0xdf0a:'REU_ACTRL'}
def dis(data, off, org, length):
    pc = org; i = off; end = off + length; out = []
    while i < end:
        op = data[i]
        if op not in OPS:
            out.append(f"{pc:04X}  {op:02X}        ???  .byte ${op:02X}"); i += 1; pc += 1; continue
        mn, m = OPS[op]; n = LEN[m]
        b = data[i:i+n]
        if len(b) < n: break
        hexs = ' '.join(f"{x:02X}" for x in b).ljust(8)
        if m == 'imp': arg = ''
        elif m == 'acc': arg = 'A'
        elif m == 'imm': arg = f"#${b[1]:02X}"
        elif m == 'zp': arg = f"${b[1]:02X}"
        elif m == 'zpx': arg = f"${b[1]:02X},X"
        elif m == 'zpy': arg = f"${b[1]:02X},Y"
        elif m in ('abs','abx','aby','ind'):
            a = b[1] | (b[2] << 8); s = REU.get(a, f"${a:04X}")
            arg = {'abs':s,'abx':s+',X','aby':s+',Y','ind':'('+s+')'}[m]
        elif m == 'inx': arg = f"(${b[1]:02X},X)"
        elif m == 'iny': arg = f"(${b[1]:02X}),Y"
        elif m == 'rel':
            t = (pc + 2 + (b[1] - 256 if b[1] > 127 else b[1])) & 0xffff; arg = f"${t:04X}"
        out.append(f"{pc:04X}  {hexs}  {mn} {arg}")
        i += n; pc += n
    return out
if __name__ == '__main__':
    f, off, org, ln = sys.argv[1], int(sys.argv[2],0), int(sys.argv[3],0), int(sys.argv[4],0)
    data = open(f,'rb').read()
    print('\n'.join(dis(data, off, org, ln)))
