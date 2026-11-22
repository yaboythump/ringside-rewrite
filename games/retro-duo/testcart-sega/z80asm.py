"""A tiny two-pass Z80 assembler: only what the Retro Duo Master System / Game Gear cart uses.

Write code as calls: a.ld_a_n(5), a.out_n_a(0xBF), a.jr_nz("loop") ... Labels resolve on assemble().
"""


class Z80:
    def __init__(self, origin=0):
        self.origin = origin
        self.items = []  # bytes, ("abs16", label), ("rel8", label) or ("label", name) / ("org", address)
        self.labels = {}

    # -- plumbing -----------------------------------------------------------------------
    def emit(self, *parts):
        for part in parts:
            self.items.append(part if isinstance(part, tuple) else bytes([part & 0xFF]))

    def label(self, name):
        self.items.append(("label", name))

    def org(self, address):
        """Pads with zeroes up to an absolute address (used for the RST/NMI vectors)."""
        self.items.append(("org", address))

    def db(self, *values):
        self.items.append(bytes(v & 0xFF for v in values))

    def dw_label(self, name):
        self.items.append(("abs16", name))

    def _word(self, value):
        return value if isinstance(value, str) else None

    def _nn(self, opcode_bytes, value):
        self.emit(*opcode_bytes)
        if isinstance(value, str):
            self.items.append(("abs16", value))
        else:
            self.emit(value & 0xFF, value >> 8 & 0xFF)

    def assemble(self):
        for final in (False, True):
            address, out = self.origin, bytearray()
            for item in self.items:
                if isinstance(item, bytes):
                    out += item
                    address += len(item)
                    continue
                kind, value = item
                if kind == "label":
                    self.labels[value] = address
                elif kind == "org":
                    if value < address:
                        raise ValueError(f"org {value:#x} is behind {address:#x}")
                    out += bytes(value - address)
                    address = value
                elif kind == "abs16":
                    target = self.labels.get(value, 0) if not final else self.labels[value]
                    out += bytes([target & 0xFF, target >> 8])
                    address += 2
                elif kind == "rel8":
                    target = self.labels.get(value, address + 1) if not final else self.labels[value]
                    offset = target - (address + 1)
                    if final and not -128 <= offset <= 127:
                        raise ValueError(f"branch to {value} out of range")
                    out.append(offset & 0xFF)
                    address += 1
        return bytes(out)

    def _rel(self, opcode, label):
        self.emit(opcode)
        self.items.append(("rel8", label))

    # -- instructions -------------------------------------------------------------------
    def di(self): self.emit(0xF3)
    def im1(self): self.emit(0xED, 0x56)
    def retn(self): self.emit(0xED, 0x45)
    def reti(self): self.emit(0xED, 0x4D)
    def ret(self): self.emit(0xC9)
    def push_af(self): self.emit(0xF5)
    def pop_af(self): self.emit(0xF1)
    def push_hl(self): self.emit(0xE5)
    def pop_hl(self): self.emit(0xE1)
    def ld_sp_nn(self, v): self._nn([0x31], v)
    def ld_hl_nn(self, v): self._nn([0x21], v)
    def ld_de_nn(self, v): self._nn([0x11], v)
    def ld_bc_nn(self, v): self._nn([0x01], v)
    def ld_a_n(self, v): self.emit(0x3E, v)
    def ld_b_n(self, v): self.emit(0x06, v)
    def ld_c_n(self, v): self.emit(0x0E, v)
    def ld_a_mem(self, v): self._nn([0x3A], v)
    def ld_mem_a(self, v): self._nn([0x32], v)
    def ld_a_hl(self): self.emit(0x7E)
    def ld_a_b(self): self.emit(0x78)
    def ld_a_c(self): self.emit(0x79)
    def ld_a_d(self): self.emit(0x7A)
    def ld_a_e(self): self.emit(0x7B)
    def ld_b_a(self): self.emit(0x47)
    def ld_c_a(self): self.emit(0x4F)
    def ld_d_a(self): self.emit(0x57)
    def ld_e_a(self): self.emit(0x5F)
    def inc_hl(self): self.emit(0x23)
    def dec_bc(self): self.emit(0x0B)
    def inc_a(self): self.emit(0x3C)
    def dec_a(self): self.emit(0x3D)
    def add_a_n(self, v): self.emit(0xC6, v)
    def sub_n(self, v): self.emit(0xD6, v)
    def and_n(self, v): self.emit(0xE6, v)
    def or_n(self, v): self.emit(0xF6, v)
    def xor_a(self): self.emit(0xAF)
    def or_c(self): self.emit(0xB1)
    def and_c(self): self.emit(0xA1)
    def cp_n(self, v): self.emit(0xFE, v)
    def cpl(self): self.emit(0x2F)
    def rlca(self): self.emit(0x07)
    def out_n_a(self, port): self.emit(0xD3, port)
    def in_a_n(self, port): self.emit(0xDB, port)
    def otir(self): self.emit(0xED, 0xB3)
    def jp(self, label): self._nn([0xC3], label)
    def call(self, label): self._nn([0xCD], label)
    def jr(self, label): self._rel(0x18, label)
    def jr_nz(self, label): self._rel(0x20, label)
    def jr_z(self, label): self._rel(0x28, label)
    def djnz(self, label): self._rel(0x10, label)
