"""A tiny two-pass 6502 assembler: just the instructions the Retro Duo NES and SNES test carts use
(the SNES cart runs in the 65816's 6502 emulation mode)."""

IMPLIED = {"sei": 0x78, "cld": 0xD8, "txs": 0x9A, "inx": 0xE8, "iny": 0xC8, "dex": 0xCA, "dey": 0x88,
           "rts": 0x60, "rti": 0x40, "clc": 0x18, "tax": 0xAA, "txa": 0x8A, "tay": 0xA8, "tya": 0x98,
           "pha": 0x48, "pla": 0x68, "lsr": 0x4A, "asl": 0x0A, "rol": 0x2A}
IMM = {"lda": 0xA9, "ldx": 0xA2, "ldy": 0xA0, "and": 0x29, "ora": 0x09, "eor": 0x49, "cmp": 0xC9,
       "cpx": 0xE0, "cpy": 0xC0, "adc": 0x69}
ZP = {"lda": 0xA5, "ldx": 0xA6, "ldy": 0xA4, "sta": 0x85, "stx": 0x86, "sty": 0x84, "inc": 0xE6,
      "dec": 0xC6, "cmp": 0xC5, "and": 0x25, "ora": 0x05, "adc": 0x65, "rol": 0x26, "bit": 0x24}
ABS = {"lda": 0xAD, "ldx": 0xAE, "ldy": 0xAC, "sta": 0x8D, "stx": 0x8E, "sty": 0x8C, "jmp": 0x4C,
       "jsr": 0x20, "bit": 0x2C, "inc": 0xEE, "dec": 0xCE, "cmp": 0xCD}
ABSX = {"lda": 0xBD, "sta": 0x9D}
ABSY = {"lda": 0xB9, "sta": 0x99}
INDY = {"lda": 0xB1, "sta": 0x91}   # (zp),y
BRANCH = {"bpl": 0x10, "bmi": 0x30, "bne": 0xD0, "beq": 0xF0, "bcc": 0x90, "bcs": 0xB0}


class Assembler:
    def __init__(self, origin):
        self.origin = origin
        self.labels = {}
        self.ops = []          # (kind, payload)

    def label(self, name):
        self.ops.append(("label", name))

    def db(self, *values):
        self.ops.append(("bytes", bytes(values)))

    def dw(self, *names):
        self.ops.append(("words", names))

    def and_(self, operand=None, mode=None):
        """`and` is a Python keyword."""
        self.ops.append(("op", ("and", operand, mode)))

    def __getattr__(self, mnemonic):
        def emit(operand=None, mode=None):
            self.ops.append(("op", (mnemonic, operand, mode)))
        return emit

    @staticmethod
    def _size(mnemonic, operand, mode):
        if operand is None:
            return 1
        if mnemonic in BRANCH or mode in ("imm", "zp", "indy"):
            return 2
        return 3

    def _encode(self, mnemonic, operand, mode, pc):
        if operand is None:
            return bytes([IMPLIED[mnemonic]])
        if isinstance(operand, str) and operand[0] in "<>":
            # "<label" / ">label": low or high byte of a label's address.
            address = self.labels[operand[1:]]
            value = address & 0xFF if operand[0] == "<" else address >> 8
        else:
            value = self.labels[operand] if isinstance(operand, str) else operand
        if mnemonic in BRANCH:
            offset = value - (pc + 2)
            assert -128 <= offset <= 127, f"branch to {operand} too far"
            return bytes([BRANCH[mnemonic], offset & 0xFF])
        if mode == "imm":
            return bytes([IMM[mnemonic], value & 0xFF])
        if mode == "zp":
            return bytes([ZP[mnemonic], value])
        if mode == "indy":
            return bytes([INDY[mnemonic], value])
        table = {"x": ABSX, "y": ABSY}.get(mode, ABS)
        return bytes([table[mnemonic], value & 0xFF, value >> 8])

    def assemble(self):
        pc = self.origin
        for kind, payload in self.ops:          # pass 1: addresses
            if kind == "label":
                self.labels[payload] = pc
            elif kind == "bytes":
                pc += len(payload)
            elif kind == "words":
                pc += 2 * len(payload)
            else:
                pc += self._size(*payload)
        out = bytearray()
        pc = self.origin
        for kind, payload in self.ops:          # pass 2: bytes
            if kind == "bytes":
                chunk = payload
            elif kind == "words":
                chunk = b"".join(self.labels[n].to_bytes(2, "little") for n in payload)
            elif kind == "op":
                chunk = self._encode(*payload, pc)
            else:
                continue
            out += chunk
            pc += len(chunk)
        return bytes(out)
