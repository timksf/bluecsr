package BlueCSR;

import List :: *;
import DReg :: *;
import BUtils :: *;
import Vector :: *;
import ModuleCollect :: *;

typedef enum {
    CSR_OKAY = 2'b00,
    CSR_EXOKAY = 2'b01,
    CSR_SLVERR = 2'b10,
    CSR_DECERR = 2'b11
} BlueCSRResponse_t deriving(Bits, Eq, FShow);

typedef enum {
    CSR_RW,
    CSR_RO,
    CSR_RC,
    CSR_WC,
    CSR_WS,
    CSR_WO,
    CSR_W1S,
    CSR_W1C
} BlueCSRAccess_t deriving(Eq, FShow);

typedef enum {
    CSR_SECURE = 1'b0,
    CSR_INSECURE = 1'b1
} BlueCSRProt_t deriving(Bits, Eq, FShow);

typedef enum {
    CSR_ALLOW_ALL,
    CSR_SEC_SECURE_ONLY,
    CSR_SEC_INSECURE_ONLY
} BlueCSRAccessPolicy_t deriving(Bits, Eq, FShow);

(*always_enabled*)
interface BlueCSR_ifc#(numeric type aw, numeric type dw);
    (*prefix = ""*) method Action valid ((*port = "i_valid"*)   Bit#(1)             valid   );
    (*prefix = ""*) method Action wr    ((*port = "i_wr"*)      Bit#(1)             wr      );
    (*prefix = ""*) method Action addr  ((*port = "i_addr"*)    Bit#(aw)            addr    );
    (*prefix = ""*) method Action wdata ((*port = "i_data"*)    Bit#(dw)            data    );
    (*prefix = ""*) method Action wstrb ((*port = "i_strb"*)    Bit#(TDiv#(dw, 8))  strb    );
    (*prefix = ""*) method Action prot  ((*port = "i_prot"*)    BlueCSRProt_t       prot    );

    (*result = "o_rdy"*)    method Bit#(1)              ready;
    (*result = "o_data"*)   method Bit#(dw)             rdata;
    (*result = "o_resp"*)   method BlueCSRResponse_t    resp;
endinterface

typedef ModuleCollect#(RegMapEntry_t#(aw, dw), ifc) BlueCSRCtx_t#(numeric type aw, numeric type dw, type ifc);

typedef struct {
    String name;
    String description;
} RegMapDef_t;

typedef struct {
    Integer offset;
    String identifier;
    String description;
} RegDef_t;

typedef struct {
    Integer offset;
    Integer length;
    String identifier;
    String description;
} RegRegionDef_t;

typedef struct {
    Integer offset;
    Integer length;
    BlueCSRAccessPolicy_t read_policy;
    BlueCSRAccessPolicy_t write_policy;
} AccessPolicyDef_t;

typedef struct {
    Integer offset;
    String identifier;
    String name;
    String description;
    Integer bit_offset;
    Integer width;
    String reset_value;
} RegFieldDef_t;

typedef struct {
    Integer offs;
    function Bit#(dw) _() f_read;
} ReadOpPure_t#(numeric type dw);

typedef struct {
    Integer offs;
    function Action _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) f_write;
} WriteOp_t#(numeric type dw);

typedef struct {
    Integer offs;
    Integer length;
    function Bit#(dw) _(Bit#(aw) a) f_read;
} ReadRegionPure_t#(numeric type aw, numeric type dw);

typedef struct {
    Integer offs;
    Integer length;
    function Action _(Bit#(aw) a, Bit#(dw) d) f_write;
} WriteRegion_t#(numeric type aw, numeric type dw);

typedef union tagged {
    RegMapDef_t       RegMapDef;
    RegDef_t          RegDef;
    RegRegionDef_t    RegRegionDef;
    AccessPolicyDef_t AccessPolicyDef;
    RegFieldDef_t     RegFieldDef;
    ReadOpPure_t#(dw) ReadOpPure;
    WriteOp_t#(dw)    WriteOp;
    ReadRegionPure_t#(aw, dw) ReadRegionPure;
    WriteRegion_t#(aw, dw) WriteRegion;
} RegMapEntry_t#(numeric type aw, numeric type dw);

function List#(ReadOpPure_t#(dw)) get_pure_read(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged ReadOpPure .rr ? Cons(rr, Nil) : Nil;
function List#(WriteOp_t#(dw)) get_write_op(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged WriteOp .rr ? Cons(rr, Nil) : Nil;
function List#(ReadRegionPure_t#(aw, dw)) get_pure_read_region(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged ReadRegionPure .rr ? Cons(rr, Nil) : Nil;
function List#(WriteRegion_t#(aw, dw)) get_write_region(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged WriteRegion .rr ? Cons(rr, Nil) : Nil;
function List#(AccessPolicyDef_t) get_access_policy_def(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged AccessPolicyDef .rr ? Cons(rr, Nil) : Nil;
function List#(RegFieldDef_t) get_regfield_def(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged RegFieldDef .rr ? Cons(rr, Nil) : Nil;
function List#(RegDef_t) get_reg_def(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged RegDef .rr ? Cons(rr, Nil) : Nil;
function List#(RegRegionDef_t) get_reg_region_def(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged RegRegionDef .rr ? Cons(rr, Nil) : Nil;
function List#(RegMapDef_t) get_regmap_def(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged RegMapDef .rr ? Cons(rr, Nil) : Nil;

typedef struct {
    String reg_defs;
} RegMapDoc_t#(numeric type dw);

typedef struct {
    Bool valid;
    String errors;
    String map_name;
    String map_description;
} RegMapValidation_t;

interface BlueCSRExport_ifc;
    method Bool done;
    method Bool success;
endinterface

typeclass FieldReadPure#(type src, numeric type dw);
    function Bit#(dw) field_read_pure(src s, Integer field_offs);
endtypeclass

instance FieldReadPure#(Reg#(t), dw) provisos(Bits#(t, st));
    function Bit#(dw) field_read_pure(Reg#(t) r, Integer field_offs);
        Bit#(dw) v = cExtend(r) << fromInteger(field_offs);
        return v;
    endfunction
endinstance

instance FieldReadPure#(t, dw) provisos(Bits#(t, st));
    function Bit#(dw) field_read_pure(t c, Integer field_offs);
        Bit#(dw) v = cExtend(c) << fromInteger(field_offs);
        return v;
    endfunction
endinstance

instance Eq#(RegDef_t);
    function Bool \== (RegDef_t ra, RegDef_t rb);
        return ra.offset == rb.offset;
    endfunction
endinstance

instance Eq#(RegRegionDef_t);
    function Bool \== (RegRegionDef_t ra, RegRegionDef_t rb);
        return ra.offset == rb.offset && ra.length == rb.length;
    endfunction
endinstance

instance Eq#(AccessPolicyDef_t);
    function Bool \== (AccessPolicyDef_t apa, AccessPolicyDef_t apb);
        return apa.offset == apb.offset && apa.length == apb.length;
    endfunction
endinstance

function Action field_write_strobed(Reg#(t) r, Integer field_offs, Bit#(dw) d, Bit#(b__) strobe)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    action
        Bit#(dw) cur_word = cExtend(r) << fromInteger(field_offs);
        Vector#(TDiv#(dw, 8), Bit#(8)) cur_bytes = unpack(cur_word);
        Vector#(TDiv#(dw, 8), Bit#(8)) wr_bytes = unpack(d);
        for (Integer i = 0; i < valueOf(b__); i = i + 1) begin
            if (unpack(strobe[i])) begin
                cur_bytes[i] = wr_bytes[i];
            end
        end
        Bit#(dw) merged_word = pack(cur_bytes);
        Bit#(st) new_field = truncate(merged_word >> fromInteger(field_offs));
        r <= unpack(new_field);
    endaction
endfunction

function Action field_w1c(Reg#(t) r, Integer field_offs, Bit#(dw) d, Bit#(b__) strb)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    action
        Bit#(dw) d_clr = cExtend(r) & ~d;
        field_write_strobed(r, field_offs, d_clr, strb);
    endaction
endfunction

function Action field_w1s(Reg#(t) r, Integer field_offs, Bit#(dw) d, Bit#(b__) strb)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    return field_write_strobed(r, field_offs, d, strb);
endfunction

function Action field_wc(Reg#(t) r, Integer field_offs, Bit#(dw) d, Bit#(b__) strb)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    return field_write_strobed(r, field_offs, 0, strb);
endfunction

function Action field_ws(Reg#(t) r, Integer field_offs, Bit#(dw) d, Bit#(b__) strb)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    action
        field_write_strobed(r, field_offs, unpack(-1), strb);
    endaction
endfunction

function Integer bit_to_integer(Bit#(n) x);
    Integer res = 0;
    for (Integer i = 0; i < valueOf(n); i = i + 1)
        if (x[i] == 1)
            res = res + 2**i;
    return res;
endfunction

function String append_newline(String acc, String msg);
    if (acc == "") return msg;
    else return acc + "\n" + msg;
endfunction

function Bool access_policy_allows(BlueCSRAccessPolicy_t policy, BlueCSRProt_t prot);
    return case (policy)
        CSR_ALLOW_ALL: True;
        CSR_SEC_SECURE_ONLY: (prot == CSR_SECURE);
        CSR_SEC_INSECURE_ONLY: (prot == CSR_INSECURE);
    endcase;
endfunction

function Integer count_regdefs_at(List#(RegDef_t) regdefs, Integer offs);
    Integer count = 0;
    for (Integer i = 0; i < length(regdefs); i = i + 1) begin
        if (regdefs[i].offset == offs) begin
            count = count + 1;
        end
    end
    return count;
endfunction

function Bool field_ranges_overlap(RegFieldDef_t a, RegFieldDef_t b);
    Integer a_lo = a.bit_offset;
    Integer a_hi = a.bit_offset + a.width;
    Integer b_lo = b.bit_offset;
    Integer b_hi = b.bit_offset + b.width;
    return (a_lo < b_hi) && (b_lo < a_hi);
endfunction

function Bool byte_ranges_overlap(Integer a_offs, Integer a_len, Integer b_offs, Integer b_len);
    return (a_offs < (b_offs + b_len)) && (b_offs < (a_offs + a_len));
endfunction

function Integer count_regions_exact(List#(RegRegionDef_t) regions, Integer offs, Integer len);
    Integer count = 0;
    for (Integer i = 0; i < length(regions); i = i + 1) begin
        if ((regions[i].offset == offs) && (regions[i].length == len)) begin
            count = count + 1;
        end
    end
    return count;
endfunction

function Integer count_access_policies_exact(List#(AccessPolicyDef_t) policies, Integer offs, Integer len);
    Integer count = 0;
    for (Integer i = 0; i < length(policies); i = i + 1) begin
        if ((policies[i].offset == offs) && (policies[i].length == len)) begin
            count = count + 1;
        end
    end
    return count;
endfunction

function String integerToHexDigitS(Integer n) = charToString(integerToHexDigit(n));

function String integerToHex(Integer n);
    if (n < 16) return integerToHexDigitS(n);
    else return strConcat(integerToHex(n / 16), integerToHexDigitS(n % 16));
endfunction

module [BlueCSRCtx_t#(aw, dw)] csr_regmap_def#(String name, String desc)();
    RegMapEntry_t#(aw, dw) entry = tagged RegMapDef RegMapDef_t {
        name: name,
        description: desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_def#(Integer offs, String ident, String desc)();
    RegMapEntry_t#(aw, dw) entry = tagged RegDef RegDef_t {
        offset: offs,
        identifier: ident,
        description: desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_def#(Integer offs, Integer len, String ident, String desc)();
    RegMapEntry_t#(aw, dw) entry = tagged RegRegionDef RegRegionDef_t {
        offset: offs,
        length: len,
        identifier: ident,
        description: desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_prot#(Integer offs, BlueCSRAccessPolicy_t read_policy, BlueCSRAccessPolicy_t write_policy)();
    RegMapEntry_t#(aw, dw) entry = tagged AccessPolicyDef AccessPolicyDef_t {
        offset: offs,
        length: valueOf(TDiv#(dw, 8)),
        read_policy: read_policy,
        write_policy: write_policy
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_prot#(Integer offs, Integer len, BlueCSRAccessPolicy_t read_policy, BlueCSRAccessPolicy_t write_policy)();
    RegMapEntry_t#(aw, dw) entry = tagged AccessPolicyDef AccessPolicyDef_t {
        offset: offs,
        length: len,
        read_policy: read_policy,
        write_policy: write_policy
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_field#(BlueCSRAccess_t access_type, Integer offs, t rv, Integer bitpos, String ident, String name, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t) r <- mkReg(rv);

    String reset_value = "0x" + integerToHex(bit_to_integer(pack(rv)));

    function Bit#(dw) do_read() = 0;
    function Action do_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) = noAction;

    case (access_type)
        CSR_RW: begin
            do_read = field_read_pure(r, bitpos);
            do_write = field_write_strobed(r, bitpos);
        end
        CSR_RO: begin
            do_read = field_read_pure(r, bitpos);
        end
        CSR_RC: begin
            do_read = field_read_pure(rv, bitpos);
        end
        CSR_WO: begin
            do_write = field_write_strobed(r, bitpos);
        end
        CSR_WC: begin
            do_read = field_read_pure(r, bitpos);
            do_write = field_wc(r, bitpos);
        end
        CSR_WS: begin
            do_read = field_read_pure(r, bitpos);
            do_write = field_ws(r, bitpos);
        end
        CSR_W1S: begin
            do_read = field_read_pure(r, bitpos);
            do_write = field_w1s(r, bitpos);
        end
        CSR_W1C: begin
            do_read = field_read_pure(r, bitpos);
            do_write = field_w1c(r, bitpos);
        end
    endcase

    RegMapEntry_t#(aw, dw) read_entry  = tagged ReadOpPure ReadOpPure_t { offs: offs, f_read: do_read };
    RegMapEntry_t#(aw, dw) write_entry = tagged WriteOp WriteOp_t { offs: offs, f_write: do_write };
    RegMapEntry_t#(aw, dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset: offs,
        identifier: ident,
        name: name,
        description: desc,
        bit_offset: bitpos,
        width: valueOf(sz_t),
        reset_value: reset_value
    };

    addToCollection(write_entry);
    addToCollection(read_entry);
    addToCollection(field_entry);

    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_rw#(Integer offs, t rv, Integer bitpos, String ident, String fname, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_field(CSR_RW, offs, rv, bitpos, ident, fname, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_ro#(Integer offs, t rv, Integer bitpos, String ident, String fname, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_field(CSR_RO, offs, rv, bitpos, ident, fname, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_rc#(Integer offs, t v, Integer bitpos, String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t) _r <- csr_reg_field(CSR_RC, offs, v, bitpos, ident, name, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_ws#(Integer offs, t rv, Integer bitpos, String ident, String name, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t) r <- csr_reg_field(CSR_WS, offs, rv, bitpos, ident, name, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_wc#(Integer offs, t rv, Integer bitpos, String ident, String name, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t) r <- csr_reg_field(CSR_WC, offs, rv, bitpos, ident, name, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_w1c#(Integer offs, t rv, Integer bitpos, String ident, String fname, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_field(CSR_W1C, offs, rv, bitpos, ident, fname, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_ro#(Integer offs, Integer len, String ident, String desc, function Bit#(dw) read_fn(Bit#(aw) local_addr))();
    function Bit#(dw) do_read(Bit#(aw) local_addr);
        return read_fn(local_addr);
    endfunction
    RegMapEntry_t#(aw, dw) read_region_entry = tagged ReadRegionPure ReadRegionPure_t {
        offs: offs,
        length: len,
        f_read: do_read
    };
    addToCollection(read_region_entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_wo#(Integer offs, Integer len, String ident, String desc, function Action write_fn(Bit#(aw) local_addr, Bit#(dw) data))();
    function Action do_write(Bit#(aw) local_addr, Bit#(dw) d);
        action
            write_fn(local_addr, d);
        endaction
    endfunction
    RegMapEntry_t#(aw, dw) write_region_entry = tagged WriteRegion WriteRegion_t {
        offs: offs,
        length: len,
        f_write: do_write
    };
    addToCollection(write_region_entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_rw#(Integer offs, Integer len, String ident, String desc, function Bit#(dw) read_fn(Bit#(aw) local_addr), function Action write_fn(Bit#(aw) local_addr, Bit#(dw) data))();
    function Bit#(dw) do_read(Bit#(aw) local_addr);
        return read_fn(local_addr);
    endfunction
    function Action do_write(Bit#(aw) local_addr, Bit#(dw) d);
        action
            write_fn(local_addr, d);
        endaction
    endfunction
    RegMapEntry_t#(aw, dw) read_region_entry = tagged ReadRegionPure ReadRegionPure_t {
        offs: offs,
        length: len,
        f_read: do_read
    };
    addToCollection(read_region_entry);
    RegMapEntry_t#(aw, dw) write_region_entry = tagged WriteRegion WriteRegion_t {
        offs: offs,
        length: len,
        f_write: do_write
    };
    addToCollection(write_region_entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

function List#(ReadOpPure_t#(dw)) find_pure_reads_by_offs(List#(ReadOpPure_t#(dw)) l, Integer offs);
    function Bool p(ReadOpPure_t#(dw) read_op) = read_op.offs == offs;
    return List::filter(p, l);
endfunction

function List#(AccessPolicyDef_t) find_policies_by_offs(List#(AccessPolicyDef_t) l, Integer offs, Integer len);
    function Bool p(AccessPolicyDef_t pol_def) = pol_def.offset == offs && pol_def.length == len;
    return List::filter(p, l);
endfunction

function List#(WriteOp_t#(dw)) find_write_ops_by_offs(List#(WriteOp_t#(dw)) l, Integer offs);
    function Bool p(WriteOp_t#(dw) write_op) = write_op.offs == offs;
    return List::filter(p, l);
endfunction

function List#(ReadRegionPure_t#(aw, dw)) find_pure_read_regions_by_range(List#(ReadRegionPure_t#(aw, dw)) l, Integer offs, Integer len);
    function Bool p(ReadRegionPure_t#(aw, dw) read_op) = read_op.offs == offs && read_op.length == len;
    return List::filter(p, l);
endfunction

function List#(WriteRegion_t#(aw, dw)) find_write_regions_by_range(List#(WriteRegion_t#(aw, dw)) l, Integer offs, Integer len);
    function Bool p(WriteRegion_t#(aw, dw) write_op) = write_op.offs == offs && write_op.length == len;
    return List::filter(p, l);
endfunction

interface BusAccess_ifc#(type ext_ifc, type int_ifc);
    interface ext_ifc external;
    interface int_ifc internal;
endinterface

typedef BusAccess_ifc#(BlueCSR_ifc#(aw, dw), int_ifc) BlueCSRAccess_ifc#(numeric type aw, numeric type dw, type int_ifc);

module [Module] create_blue_csr#(BlueCSRCtx_t#(aw, dw, i) ctx)(BlueCSRAccess_ifc#(aw, dw, i));
    let {coll_device_ifc, c} <- getCollection(ctx);

    let regdefs = List::concat(List::map(get_reg_def, c));
    let regiondefs = List::concat(List::map(get_reg_region_def, c));
    let access_policies = List::concat(List::map(get_access_policy_def, c));
    let pure_reads = List::concat(List::map(get_pure_read, c));
    let pure_read_regions = List::concat(List::map(get_pure_read_region, c));
    let write_ops = List::concat(List::map(get_write_op, c));
    let write_regions = List::concat(List::map(get_write_region, c));

    Integer word_bytes = valueOf(TDiv#(dw, 8));

    Reg#(Bit#(1))               rg_valid    <- mkDReg(0);
    Reg#(Bit#(1))               rg_wr       <- mkReg(0);
    Reg#(Bit#(aw))              rg_addr     <- mkReg(0);
    Reg#(Bit#(dw))              rg_wdata    <- mkReg(0);
    Reg#(Bit#(TDiv#(dw, 8)))    rg_wstrb    <- mkReg(0);
    Reg#(BlueCSRProt_t)         rg_prot     <- mkDReg(CSR_INSECURE);

    Wire#(Bit#(dw)) w_rdata <- mkDWire(0);
    Wire#(BlueCSRResponse_t) w_resp <- mkDWire(CSR_OKAY);

    function Bit#(dw) combine_reads(List#(ReadOpPure_t#(dw)) l);
        function Bit#(dw) fold_read(Bit#(dw) acc, ReadOpPure_t#(dw) rop);
            return acc | rop.f_read();
        endfunction
        return List::foldl(fold_read, 0, l);
    endfunction

    function Action dispatch_reg_writes(List#(WriteOp_t#(dw)) l, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe);
        function Action fold_write(Action acc, WriteOp_t#(dw) op);
            return action
                acc;
                op.f_write(data, strobe);
            endaction;
        endfunction
        return List::foldl(fold_write, noAction, l);
    endfunction

    function Bool is_word_aligned(Bit#(aw) addr);
        return (bit_to_integer(addr) % word_bytes) == 0;
    endfunction

    function Bool is_region_addr(Bit#(aw) addr, Integer offs, Integer len);
        return (addr >= fromInteger(offs)) && (addr < fromInteger(offs + len));
    endfunction

    Rules read_rules = emptyRules;
    Rules write_rules = emptyRules;

    for (Integer i = 0; i < List::length(regdefs); i = i + 1) begin
        let field_reads = find_pure_reads_by_offs(pure_reads, regdefs[i].offset);
        let reg_policies = find_policies_by_offs(access_policies, regdefs[i].offset, word_bytes);
        let read_policy = List::length(reg_policies) > 0 ? reg_policies[0].read_policy : CSR_ALLOW_ALL;
        let write_policy = List::length(reg_policies) > 0 ? reg_policies[0].write_policy : CSR_ALLOW_ALL;

        read_rules = rJoinMutuallyExclusive(rules
            rule rread_reg_allow((rg_valid == 1'b1) && (rg_wr == 1'b0) && (rg_addr == fromInteger(regdefs[i].offset)) && access_policy_allows(read_policy, rg_prot));
                w_rdata <= combine_reads(field_reads);
                w_resp <= CSR_OKAY;
            endrule
            //when a read is denied, the default rule will fire
        endrules, read_rules);

        write_rules = rJoinMutuallyExclusive(rules
            rule rwrite_reg_allow((rg_valid == 1'b1) && (rg_wr == 1'b1) && (rg_addr == fromInteger(regdefs[i].offset)) && access_policy_allows(write_policy, rg_prot));
                let reg_writes = find_write_ops_by_offs(write_ops, regdefs[i].offset);
                dispatch_reg_writes(reg_writes, rg_wdata, rg_wstrb);
                w_resp <= CSR_OKAY;
            endrule
            //when a write is denied, the default rule will fire
        endrules, write_rules);
    end

    for (Integer i = 0; i < List::length(regiondefs); i = i + 1) begin
        let region_reads = find_pure_read_regions_by_range(pure_read_regions, regiondefs[i].offset, regiondefs[i].length);
        let region_writes = find_write_regions_by_range(write_regions, regiondefs[i].offset, regiondefs[i].length);
        let region_policies = find_policies_by_offs(access_policies, regiondefs[i].offset, regiondefs[i].length);
        let read_policy = List::length(region_policies) > 0 ? region_policies[0].read_policy : CSR_ALLOW_ALL;
        let write_policy = List::length(region_policies) > 0 ? region_policies[0].write_policy : CSR_ALLOW_ALL;

        read_rules = rJoinMutuallyExclusive(rules
            rule rread_region_allow((rg_valid == 1'b1) && (rg_wr == 1'b0) && is_region_addr(rg_addr, regiondefs[i].offset, regiondefs[i].length) && is_word_aligned(rg_addr) && access_policy_allows(read_policy, rg_prot));
                Bit#(dw) read_data = (List::length(region_reads) > 0) ? region_reads[0].f_read(rg_addr - fromInteger(regiondefs[i].offset)) : 0;
                w_rdata <= read_data;
                w_resp <= CSR_OKAY;
            endrule
        endrules, read_rules);

        // write_rules = rJoinMutuallyExclusive(rules
        //     rule rwrite_region_allow((rg_valid == 1'b1) && (rg_wr == 1'b1) && is_region_addr(rg_addr, regiondefs[i].offset, regiondefs[i].length) && is_word_aligned(rg_addr) && (rg_wstrb == '1) && access_policy_allows(write_policy, rg_prot));
        //         if (List::length(region_writes) > 0) begin
        //             region_writes[0].f_write(rg_addr - fromInteger(regiondefs[i].offset), rg_wdata);
        //         end
        //         w_resp <= CSR_OKAY;
        //     endrule
        //     rule rwrite_region_deny((rg_valid == 1'b1) && (rg_wr == 1'b1) && is_region_addr(rg_addr, regiondefs[i].offset, regiondefs[i].length) && (!is_word_aligned(rg_addr) || (rg_wstrb != '1) || !access_policy_allows(write_policy, rg_prot)));
        //         w_resp <= CSR_SLVERR;
        //     endrule
        // endrules, write_rules);
    end

    read_rules = rJoinDescendingUrgency(read_rules,
        rules
            rule rread_default((rg_valid == 1'b1) && (rg_wr == 1'b0));
                w_rdata <= 0;
                w_resp <= CSR_DECERR;
            endrule
        endrules
    );

    write_rules = rJoinDescendingUrgency(write_rules,
        rules
            rule rwrite_default((rg_valid == 1'b1) && (rg_wr == 1'b1));
                w_resp <= CSR_DECERR;
            endrule
        endrules
    );

    addRules(read_rules);
    addRules(write_rules);

    interface BlueCSR_ifc external;
        method Action valid(Bit#(1) valid_i);
            rg_valid <= valid_i;
        endmethod

        method Action wr(Bit#(1) wr_i);
            rg_wr <= wr_i;
        endmethod

        method Action addr(Bit#(aw) addr_i);
            rg_addr <= addr_i;
        endmethod

        method Action wdata(Bit#(dw) data_i);
            rg_wdata <= data_i;
        endmethod

        method Action wstrb(Bit#(TDiv#(dw, 8)) strb_i);
            rg_wstrb <= strb_i;
        endmethod

        method Action prot(BlueCSRProt_t prot_i);
            rg_prot <= prot_i;
        endmethod

        method Bit#(1) ready;
            return 1'b1;
        endmethod

        method Bit#(dw) rdata;
            return ((rg_valid == 1'b1) && (rg_wr == 1'b0)) ? w_rdata : 0;
        endmethod

        method BlueCSRResponse_t resp;
            return (rg_valid == 1'b1) ? w_resp : CSR_OKAY;
        endmethod
    endinterface

    interface internal = coll_device_ifc;
endmodule

endpackage
