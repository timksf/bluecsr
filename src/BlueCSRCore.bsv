package BlueCSRCore;

import List :: *;
import DReg :: *;
import FIFO :: *;
import FIFOF :: *;
import BUtils :: *;
import Vector :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
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
} BlueCSRAccess_t deriving(Bits, Eq, FShow);

typedef enum {
    CSR_SECURE = 1'b0,
    CSR_INSECURE = 1'b1
} BlueCSRProt_t deriving(Bits, Eq, FShow);

typedef enum {
    CSR_ALLOW_ALL,
    CSR_SEC_SECURE_ONLY,
    CSR_SEC_INSECURE_ONLY
} BlueCSRAccessPolicy_t deriving(Bits, Eq, FShow);

typedef enum {
    TRIG_RO,
    TRIG_WO,
    TRIG_RW
} BlueCSRTrigger_t deriving(Bits, Eq, FShow);

typedef struct {
    Bool wr;
    Bit#(aw) addr;
    Bit#(dw) wdata;
    Bit#(TDiv#(dw, 8)) wstrb;
    BlueCSRProt_t prot;
} BlueCSR_Req_t#(numeric type aw, numeric type dw) deriving(Eq, Bits, FShow);

typedef struct {
    Bit#(dw) rdata;
    BlueCSRResponse_t resp;
} BlueCSR_Rsp_t#(numeric type dw) deriving(Eq, Bits, FShow);

(*always_enabled*)
interface BlueCSR_Fab_ifc#(numeric type aw, numeric type dw);
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

interface BlueCSR_ifc#(numeric type aw, numeric type dw);
    //no pure server to allow easy expansion of this interface
    interface Put#(BlueCSR_Req_t#(aw, dw))  request;
    interface Get#(BlueCSR_Rsp_t#(dw))      response;
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
    BlueCSRAccess_t access_type;
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
    Bool exclusive;
    function Bool _() can_read;
    BlueCSR_Rsp_t#(dw) unavailable_rsp;
    function ActionValue#(BlueCSR_Rsp_t#(dw)) _() f_read;
} ReadOpAction_t#(numeric type dw);

typedef struct {
    Integer offs;
    function Action _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) f_write;
} WriteOp_t#(numeric type dw);

typedef struct {
    Integer offs;
    Bool exclusive;
    function Bool _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) can_write;
    BlueCSRResponse_t unavailable_resp;
    function ActionValue#(BlueCSRResponse_t) _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) f_write;
} WriteOpAction_t#(numeric type dw);

typedef struct {
    Integer offs;
    Integer length;
    function Bit#(dw) _(Bit#(aw) a) f_read;
} ReadRegion_t#(numeric type aw, numeric type dw);

typedef struct {
    Integer offs;
    Integer length;
    function Action _(Bit#(aw) a, Bit#(dw) d) f_write;
} WriteRegion_t#(numeric type aw, numeric type dw);

typedef struct {
    Integer offs;
    Bool delay;
    function Action _() trigger;
} ReadTrigger_t;

typedef struct {
    Integer offs;
    Bool delay;
    function Action _() trigger;
} WriteTrigger_t;

typedef union tagged {
    RegMapDef_t             RegMapDef;
    RegDef_t                RegDef;
    RegRegionDef_t          RegRegionDef;
    AccessPolicyDef_t       AccessPolicyDef;
    RegFieldDef_t           RegFieldDef;
    ReadOpPure_t#(dw)       ReadOpPure;
    ReadOpAction_t#(dw)     ReadOpAction;
    WriteOp_t#(dw)          WriteOp;
    WriteOpAction_t#(dw)    WriteOpAction;
    ReadRegion_t#(aw, dw)   ReadRegion;
    WriteRegion_t#(aw, dw)  WriteRegion;
    ReadTrigger_t           ReadTrigger;
    WriteTrigger_t          WriteTrigger;
} RegMapEntry_t#(numeric type aw, numeric type dw);

function List#(ReadOpPure_t#(dw)) get_pure_read(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged ReadOpPure .rr ? Cons(rr, Nil) : Nil;
function List#(ReadOpAction_t#(dw)) get_action_read(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged ReadOpAction .rr ? Cons(rr, Nil) : Nil;
function List#(WriteOp_t#(dw)) get_write_op(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged WriteOp .rr ? Cons(rr, Nil) : Nil;
function List#(WriteOpAction_t#(dw)) get_action_write(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged WriteOpAction .rr ? Cons(rr, Nil) : Nil;
function List#(ReadRegion_t#(aw, dw)) get_read_region(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged ReadRegion .rr ? Cons(rr, Nil) : Nil;
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
function List#(ReadTrigger_t) get_read_trigger(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged ReadTrigger .rr ? Cons(rr, Nil) : Nil;
function List#(WriteTrigger_t) get_write_trigger(RegMapEntry_t#(aw, dw) regmap_entry) =
    regmap_entry matches tagged WriteTrigger .rr ? Cons(rr, Nil) : Nil;


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

function Bool is_power_of_two(Integer value);
    Bool result = value > 0;
    Integer remaining = value;
    while (remaining > 1) begin
        result = result && ((remaining % 2) == 0);
        remaining = remaining / 2;
    end
    return result;
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
    if(len <= 0) begin
        errorM("BlueCSR region " + ident + " has non-positive length.");
    end
    else if(!is_power_of_two(len)) begin
        errorM("BlueCSR region " + ident + " length must be a power of two for mask-based address decoding.");
    end
    else if((offs % len) != 0) begin
        errorM("BlueCSR region " + ident + " offset must be aligned to its length for mask-based address decoding.");
    end

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

module [BlueCSRCtx_t#(aw, dw)] csr_region_wo#(Integer offs, Integer len, function Action write_fn(Bit#(aw) local_addr, Bit#(dw) data), String ident, String desc)();
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

module [BlueCSRCtx_t#(aw, dw)] csr_region_rw#(Integer offs, Integer len, function Bit#(ldw) read_fn(Bit#(law) local_addr), function Action write_fn(Bit#(lawaw) local_addr, Bit#(ldw) data), String ident, String desc)();
    function Bit#(dw) do_read(Bit#(aw) local_addr);
        return cExtend(read_fn(cExtend(local_addr)));
    endfunction
    function Action do_write(Bit#(aw) local_addr, Bit#(dw) d);
        action
            write_fn(cExtend(local_addr), cExtend(d));
        endaction
    endfunction
    RegMapEntry_t#(aw, dw) read_region_entry = tagged ReadRegion ReadRegion_t {
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
        access_type: access_type,
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

module [BlueCSRCtx_t#(aw, dw)] csr_reg_wo#(Integer offs, t rv, Integer bitpos, String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t) _r <- csr_reg_field(CSR_WO, offs, rv, bitpos, ident, name, desc);
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

module [BlueCSRCtx_t#(aw, dw)] csr_reg_w1c_evt#(Integer offs, Bool rv, Bool evt, Integer bitpos, String ident, String fname, String desc)()
    provisos(
        Add#(1, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(Bool) r <- mkReg(rv);
    Wire#(Bool) w_clear <- mkDWire(False);

    String reset_value = "0x" + integerToHex(bit_to_integer(pack(rv)));

    rule update;
        r <= (r && !w_clear) || evt;
    endrule

    function Bit#(dw) do_read() = field_read_pure(r, bitpos);

    function Action do_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        action
            w_clear <= unpack(d[bitpos] & s[bitpos / 8]);
        endaction
    endfunction

    RegMapEntry_t#(aw, dw) read_entry = tagged ReadOpPure ReadOpPure_t {
        offs: offs,
        f_read: do_read
    };
    RegMapEntry_t#(aw, dw) write_entry = tagged WriteOp WriteOp_t {
        offs: offs,
        f_write: do_write
    };
    RegMapEntry_t#(aw, dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset: offs,
        identifier: ident,
        name: fname,
        description: desc,
        access_type: CSR_W1C,
        bit_offset: bitpos,
        width: 1,
        reset_value: reset_value
    };

    addToCollection(write_entry);
    addToCollection(read_entry);
    addToCollection(field_entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_w1s#(Integer offs, t rv, Integer bitpos, String ident, String fname, String desc)(Reg#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_field(CSR_W1S, offs, rv, bitpos, ident, fname, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_fifo_ro#(Integer offs, FIFOF#(t) fifo, String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, unused_width, dw),
        Mul#(TDiv#(sz_t, 8), 8, sz_t),
        Div#(sz_t, 8, TDiv#(sz_t, 8))
    );
    function Bool can_read() = fifo.notEmpty;

    function ActionValue#(BlueCSR_Rsp_t#(dw)) do_read();
        actionvalue
            Bit#(dw) data = zeroExtend(pack(fifo.first));
            fifo.deq;
            return BlueCSR_Rsp_t { rdata: data, resp: CSR_OKAY };
        endactionvalue
    endfunction

    RegMapEntry_t#(aw, dw) read_entry = tagged ReadOpAction ReadOpAction_t {
        offs: offs,
        exclusive: True,
        can_read: can_read,
        unavailable_rsp: BlueCSR_Rsp_t { rdata: 0, resp: CSR_SLVERR },
        f_read: do_read
    };
    RegMapEntry_t#(aw, dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset: offs,
        identifier: ident,
        name: name,
        description: desc,
        access_type: CSR_RO,
        bit_offset: 0,
        width: valueOf(sz_t),
        reset_value: "0x0"
    };

    addToCollection(read_entry);
    addToCollection(field_entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_fifo_ro_valid#(Integer offs, FIFOF#(t) fifo, String data_ident, String data_name, String data_desc, String valid_ident, String valid_name, String valid_desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, data_unused_width, dw),
        Add#(sz_t, 1, used_width),
        Add#(used_width, unused_width, dw),
        Mul#(TDiv#(sz_t, 8), 8, sz_t),
        Div#(sz_t, 8, TDiv#(sz_t, 8))
    );
    function Bool can_read() = fifo.notEmpty;

    function ActionValue#(BlueCSR_Rsp_t#(dw)) do_read();
        actionvalue
            Bit#(dw) data = zeroExtend(pack(fifo.first));
            data[valueOf(sz_t)] = 1;
            fifo.deq;
            return BlueCSR_Rsp_t { rdata: data, resp: CSR_OKAY };
        endactionvalue
    endfunction

    RegMapEntry_t#(aw, dw) read_entry = tagged ReadOpAction ReadOpAction_t {
        offs: offs,
        exclusive: False,
        can_read: can_read,
        unavailable_rsp: BlueCSR_Rsp_t { rdata: 0, resp: CSR_OKAY },
        f_read: do_read
    };
    RegMapEntry_t#(aw, dw) data_field_entry = tagged RegFieldDef RegFieldDef_t {
        offset: offs,
        identifier: data_ident,
        name: data_name,
        description: data_desc,
        access_type: CSR_RO,
        bit_offset: 0,
        width: valueOf(sz_t),
        reset_value: "0x0"
    };
    RegMapEntry_t#(aw, dw) valid_field_entry = tagged RegFieldDef RegFieldDef_t {
        offset: offs,
        identifier: valid_ident,
        name: valid_name,
        description: valid_desc,
        access_type: CSR_RO,
        bit_offset: valueOf(sz_t),
        width: 1,
        reset_value: "0x0"
    };

    addToCollection(read_entry);
    addToCollection(data_field_entry);
    addToCollection(valid_field_entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_fifo_wo#(Integer offs, FIFOF#(t) fifo, String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, unused_width, dw),
        Add#(TDiv#(sz_t, 8), unused_strobes, TDiv#(dw, 8)),
        Mul#(TDiv#(sz_t, 8), 8, sz_t),
        Div#(sz_t, 8, TDiv#(sz_t, 8)),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Bit#(TDiv#(sz_t, 8)) fifo_strobes = unpack(-1);
    Bit#(TDiv#(dw, 8)) required_strobes = zeroExtend(fifo_strobes);

    function Bool can_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        return (s != required_strobes) || fifo.notFull;
    endfunction

    function ActionValue#(BlueCSRResponse_t) do_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        actionvalue
            if (s == required_strobes) begin
                fifo.enq(unpack(truncate(d)));
            end
            return (s == required_strobes) ? CSR_OKAY : CSR_SLVERR;
        endactionvalue
    endfunction

    RegMapEntry_t#(aw, dw) write_entry = tagged WriteOpAction WriteOpAction_t {
        offs: offs,
        exclusive: True,
        can_write: can_write,
        unavailable_resp: CSR_SLVERR,
        f_write: do_write
    };
    RegMapEntry_t#(aw, dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset: offs,
        identifier: ident,
        name: name,
        description: desc,
        access_type: CSR_WO,
        bit_offset: 0,
        width: valueOf(sz_t),
        reset_value: "0x0"
    };

    addToCollection(write_entry);
    addToCollection(field_entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_ro#(Integer offs, Integer len, function Bit#(dw) read_fn(Bit#(aw) local_addr), String ident, String desc)();
    function Bit#(dw) do_read(Bit#(aw) local_addr);
        return read_fn(local_addr);
    endfunction
    RegMapEntry_t#(aw, dw) read_region_entry = tagged ReadRegion ReadRegion_t {
        offs: offs,
        length: len,
        f_read: do_read
    };
    addToCollection(read_region_entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule


module [BlueCSRCtx_t#(aw, dw)] csr_reg_trig#(Integer offs, Bool delay, BlueCSRTrigger_t rw, String ident, String name, String desc)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(Bit#(1)) rg_trig;
    
    if(!delay)
        rg_trig <- mkDWire(0);
    else
        rg_trig <- mkDReg(0);

    function Action f_trigger();
        action
            rg_trig <= 1'b1;
        endaction
    endfunction

    if(rw == TRIG_RO || rw == TRIG_RW) begin
        RegMapEntry_t#(aw, dw) entry = tagged ReadTrigger ReadTrigger_t { offs: offs, delay: delay, trigger: f_trigger };
        addToCollection(entry);
    end if(rw == TRIG_WO || rw == TRIG_RW) begin
        RegMapEntry_t#(aw, dw) entry = tagged WriteTrigger WriteTrigger_t { offs: offs, delay: delay, trigger: f_trigger };
        addToCollection(entry);
    end
    return rg_trig;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trigr#(Integer offs, Bool delay, String ident, String name, String desc)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_trig(offs, delay, TRIG_RO, ident, name, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trigw#(Integer offs, Bool delay, String ident, String name, String desc)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_trig(offs, delay, TRIG_WO, ident, name, desc);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trigrw#(Integer offs, Bool delay, String ident, String name, String desc)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_trig(offs, delay, TRIG_RW, ident, name, desc);
    return r;
endmodule

function List#(ReadOpPure_t#(dw)) find_pure_reads_by_offs(List#(ReadOpPure_t#(dw)) l, Integer offs);
    function Bool p(ReadOpPure_t#(dw) read_op) = read_op.offs == offs;
    return List::filter(p, l);
endfunction

function List#(ReadOpAction_t#(dw)) find_action_reads_by_offs(List#(ReadOpAction_t#(dw)) l, Integer offs);
    function Bool p(ReadOpAction_t#(dw) read_op) = read_op.offs == offs;
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

function List#(WriteOpAction_t#(dw)) find_action_writes_by_offs(List#(WriteOpAction_t#(dw)) l, Integer offs);
    function Bool p(WriteOpAction_t#(dw) write_op) = write_op.offs == offs;
    return List::filter(p, l);
endfunction

function List#(ReadTrigger_t) find_rtrig_by_offs(List#(ReadTrigger_t) l, Integer offs);
    function Bool p(ReadTrigger_t rtrig) = rtrig.offs == offs;
    return List::filter(p, l);
endfunction

function List#(WriteTrigger_t) find_wtrig_by_offs(List#(WriteTrigger_t) l, Integer offs);
    function Bool p(WriteTrigger_t wtrig) = wtrig.offs == offs;
    return List::filter(p, l);
endfunction

function List#(ReadRegion_t#(aw, dw)) find_read_regions_by_range(List#(ReadRegion_t#(aw, dw)) l, Integer offs, Integer len);
    function Bool p(ReadRegion_t#(aw, dw) read_op) = read_op.offs == offs && read_op.length == len;
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

typedef BusAccess_ifc#(BlueCSR_Fab_ifc#(aw, dw), int_ifc)   BlueCSRAccess_Fab_ifc#(numeric type aw, numeric type dw, type int_ifc);
typedef BusAccess_ifc#(BlueCSR_ifc#(aw, dw), int_ifc)       BlueCSRAccess_ifc#(numeric type aw, numeric type dw, type int_ifc);

module [Module] create_blue_csr#(
        BlueCSRCtx_t#(aw, dw, i) ctx,
        Bool buffer_in
    )(BlueCSRAccess_ifc#(aw, dw, i));

    let {coll_device_ifc, c} <- getCollection(ctx);

    // let validation = validate_blue_csr_entries(c);
    // if (!validation.valid) begin
    //     errorM(validation.errors);
    // end

    let regdefs         = List::concat(List::map(get_reg_def, c));
    let regiondefs      = List::concat(List::map(get_reg_region_def, c));
    let access_policies = List::concat(List::map(get_access_policy_def, c));
    let pure_reads      = List::concat(List::map(get_pure_read, c));
    let action_reads    = List::concat(List::map(get_action_read, c));
    let read_regions    = List::concat(List::map(get_read_region, c));
    let write_ops       = List::concat(List::map(get_write_op, c));
    let action_writes   = List::concat(List::map(get_action_write, c));
    let write_regions   = List::concat(List::map(get_write_region, c));
    let read_triggers   = List::concat(List::map(get_read_trigger, c));
    let write_triggers  = List::concat(List::map(get_write_trigger, c));

    Integer word_bytes = valueOf(TDiv#(dw, 8));

    FIFOF#(BlueCSR_Req_t#(aw, dw))  f_req;
    FIFOF#(BlueCSR_Rsp_t#(dw))      f_rsp <- mkBypassFIFOF;

    //the requests are still buffered with the bypass fifo 
    //but only when there is no space in the output. Otherwise, the
    //request is processed combinationally
    if(!buffer_in)
        f_req <- mkBypassFIFOF;
    else
        f_req <- mkSizedFIFOF(1);


    // Reg#(Bit#(1))               rg_valid    <- mkDReg(0);
    // Reg#(Bit#(1))               rg_wr       <- mkReg(0);
    // Reg#(Bit#(aw))              rg_addr     <- mkReg(0);
    // Reg#(Bit#(dw))              rg_wdata    <- mkReg(0);
    // Reg#(Bit#(TDiv#(dw, 8)))    rg_wstrb    <- mkReg(0);
    // Reg#(BlueCSRProt_t)         rg_prot     <- mkDReg(CSR_INSECURE);

    // Wire#(Bit#(dw))             w_rdata <- mkDWire(0);
    // Wire#(BlueCSRResponse_t)    w_resp  <- mkDWire(CSR_SLVERR);

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
        Bit#(aw) byte_mask = fromInteger(word_bytes - 1);
        return (addr & byte_mask) == 0;
    endfunction

    function Bool is_region_addr(Bit#(aw) addr, Integer offs, Integer len);
        Bit#(aw) region_mask = ~fromInteger(len - 1);
        Bit#(aw) region_base = fromInteger(offs);
        return (addr & region_mask) == region_base;
    endfunction

    Rules read_rules = emptyRules;
    Rules write_rules = emptyRules;

    for (Integer i = 0; i < List::length(regdefs); i = i + 1) begin
        let field_reads     = find_pure_reads_by_offs(pure_reads, regdefs[i].offset);
        let field_actions   = find_action_reads_by_offs(action_reads, regdefs[i].offset);
        let rtrigs          = find_rtrig_by_offs(read_triggers, regdefs[i].offset);
        let wtrigs          = find_wtrig_by_offs(write_triggers, regdefs[i].offset);
        let reg_policies    = find_policies_by_offs(access_policies, regdefs[i].offset, word_bytes);
        let reg_writes      = find_write_ops_by_offs(write_ops, regdefs[i].offset);
        let write_actions   = find_action_writes_by_offs(action_writes, regdefs[i].offset);

        if (List::length(field_actions) > 1) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has multiple action reads.");
        end
        if ((List::length(field_actions) == 1) && field_actions[0].exclusive && (List::length(field_reads) > 0)) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has an exclusive action read mixed with value reads.");
        end
        if (List::length(write_actions) > 1) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has multiple action writes.");
        end
        if ((List::length(write_actions) == 1) && write_actions[0].exclusive && (List::length(reg_writes) > 0)) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has an exclusive action write mixed with other writes.");
        end

        let read_policy     = List::length(reg_policies) > 0 ? reg_policies[0].read_policy : CSR_ALLOW_ALL;
        let write_policy    = List::length(reg_policies) > 0 ? reg_policies[0].write_policy : CSR_ALLOW_ALL;

        let req             = f_req.first;
        let req_hit         = (req.addr == fromInteger(regdefs[i].offset));
        let req_rd_allowed  = access_policy_allows(read_policy,  req.prot);
        let req_wr_allowed  = access_policy_allows(write_policy, req.prot);

        //TODO: should triggers align with data output? (difficult as it moves through arbitrarily delayed FIFOs)

        if (List::length(field_actions) == 0) begin
            read_rules = rJoinMutuallyExclusive(rules
                rule rread_reg_allow(!req.wr && req_hit && req_rd_allowed);
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata:  combine_reads(field_reads),
                            resp:   CSR_OKAY
                        }
                    );
                    if(List::length(rtrigs) > 0)
                        rtrigs[0].trigger;
                    f_req.deq;
                endrule
            endrules, read_rules);
        end
        else begin
            read_rules = rJoinMutuallyExclusive(rules
                rule rread_reg_action_available(!req.wr && req_hit && req_rd_allowed && field_actions[0].can_read);
                    let action_rsp <- field_actions[0].f_read;
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata:  combine_reads(field_reads) | action_rsp.rdata,
                            resp:   action_rsp.resp
                        }
                    );
                    if(List::length(rtrigs) > 0)
                        rtrigs[0].trigger;
                    f_req.deq;
                endrule
                rule rread_reg_action_unavailable(!req.wr && req_hit && req_rd_allowed && !field_actions[0].can_read);
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata: combine_reads(field_reads) | field_actions[0].unavailable_rsp.rdata,
                            resp: field_actions[0].unavailable_rsp.resp
                        }
                    );
                    if(List::length(rtrigs) > 0)
                        rtrigs[0].trigger;
                    f_req.deq;
                endrule
            endrules, read_rules);
        end

        if (List::length(write_actions) == 0) begin
            write_rules = rJoinMutuallyExclusive(rules
                rule rwrite_reg_allow(req.wr && req_hit && req_wr_allowed);
                    dispatch_reg_writes(reg_writes, req.wdata, req.wstrb);
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata:  ?,
                            resp:   CSR_OKAY
                        }
                    );
                    if(List::length(wtrigs) > 0)
                        wtrigs[0].trigger;
                    f_req.deq;
                endrule
            endrules, write_rules);
        end
        else begin
            write_rules = rJoinMutuallyExclusive(rules
                rule rwrite_reg_action_available(req.wr && req_hit && req_wr_allowed && write_actions[0].can_write(req.wdata, req.wstrb));
                    let action_resp <- write_actions[0].f_write(req.wdata, req.wstrb);
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata: ?,
                            resp: action_resp
                        }
                    );
                    if(List::length(wtrigs) > 0)
                        wtrigs[0].trigger;
                    f_req.deq;
                endrule
                rule rwrite_reg_action_unavailable(req.wr && req_hit && req_wr_allowed && !write_actions[0].can_write(req.wdata, req.wstrb));
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata: ?,
                            resp: write_actions[0].unavailable_resp
                        }
                    );
                    if(List::length(wtrigs) > 0)
                        wtrigs[0].trigger;
                    f_req.deq;
                endrule
            endrules, write_rules);
        end
    end

    for (Integer i = 0; i < List::length(regiondefs); i = i + 1) begin
        let region_reads    = find_read_regions_by_range(read_regions, regiondefs[i].offset, regiondefs[i].length);
        let region_writes   = find_write_regions_by_range(write_regions, regiondefs[i].offset, regiondefs[i].length);
        let region_policies = find_policies_by_offs(access_policies, regiondefs[i].offset, regiondefs[i].length);

        let read_policy     = List::length(region_policies) > 0 ? region_policies[0].read_policy : CSR_ALLOW_ALL;
        let write_policy    = List::length(region_policies) > 0 ? region_policies[0].write_policy : CSR_ALLOW_ALL;

        let req             = f_req.first;
        Bit#(aw) local_addr = req.addr - fromInteger(regiondefs[i].offset);
        let req_hit         = is_region_addr(req.addr, regiondefs[i].offset, regiondefs[i].length);
        let req_aligned     = is_word_aligned(req.addr);
        let req_rd_allowed  = access_policy_allows(read_policy,  req.prot);
        let req_wr_allowed  = access_policy_allows(write_policy, req.prot);
        //region writes are only valid for entire words
        let req_wr_valid    = req.wstrb == unpack(-1);

        read_rules = rJoinMutuallyExclusive(rules
            rule rread_region_allow(!req.wr && req_hit && req_aligned && req_rd_allowed);
                Bit#(dw) read_data = (List::length(region_reads) > 0) ? region_reads[0].f_read(local_addr) : 0;
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  read_data,
                        resp:   CSR_OKAY
                    }
                );
                f_req.deq;
            endrule
        endrules, read_rules);

        write_rules = rJoinMutuallyExclusive(rules
            rule rwrite_region_allow(req.wr && req_hit && req_aligned && req_wr_valid && req_wr_allowed);
                if (List::length(region_writes) > 0) begin
                    region_writes[0].f_write(local_addr, req.wdata);
                end
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  ?,
                        resp:   CSR_OKAY
                    }
                );
                f_req.deq;
                //region writes are only allowed for fully enabled strobes
            endrule
        endrules, write_rules);
    end

    read_rules = rJoinDescendingUrgency(read_rules,
        rules
            rule rread_default(!f_req.first.wr); //only fires if a request is available
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  0,
                        resp:   CSR_DECERR
                    }
                );
                f_req.deq;
            endrule
        endrules
    );

    write_rules = rJoinDescendingUrgency(write_rules,
        rules
            rule rwrite_default(f_req.first.wr);
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  ?,
                        resp:   CSR_DECERR
                    }
                );
                f_req.deq;
            endrule
        endrules
    );

    addRules(read_rules);
    addRules(write_rules);

    interface BlueCSR_ifc external;
        interface request  = toPut(f_req);
        interface response = toGet(f_rsp);
    endinterface

    interface internal = coll_device_ifc;
endmodule

endpackage
