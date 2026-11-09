package BlueCSRCore;

import List :: *;
import DReg :: *;
import FIFOF :: *;
import BUtils :: *;
import Vector :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import ModuleCollect :: *;
import ClientServer :: *;
import BRAM :: *;
import DefaultValue :: *;

import BlueCSRTypes :: *;
import BlueCSRValidation :: *;

export BlueCSRTypes :: *;
export BlueCSRCore :: *;

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

//field value after a byte strobed bus write of d onto current
function t field_value_strobed(t current, Integer field_offs, Bit#(dw) d, Bit#(b__) strobe)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    Bit#(dw)                       cur_word  = cExtend(current) << fromInteger(field_offs);
    Vector#(TDiv#(dw, 8), Bit#(8)) cur_bytes = unpack(cur_word);
    Vector#(TDiv#(dw, 8), Bit#(8)) wr_bytes  = unpack(d);
    for (Integer i = 0; i < valueOf(b__); i = i + 1) begin
        if(unpack(strobe[i])) begin
            cur_bytes[i] = wr_bytes[i];
        end
    end
    Bit#(dw) merged_word = pack(cur_bytes);
    Bit#(st) new_field   = truncate(merged_word >> fromInteger(field_offs));
    return unpack(new_field);
endfunction

function Action field_write_strobed(Reg#(t) r, Integer field_offs, Bit#(dw) d, Bit#(b__) strobe)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    action
        r <= field_value_strobed(r, field_offs, d, strobe);
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
        Bit#(dw) current = cExtend(r) << fromInteger(field_offs);
        Bit#(dw) d_clr   = current & ~d;
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
    action
        Bit#(dw) current = cExtend(r) << fromInteger(field_offs);
        Bit#(dw) d_set   = current | d;
        field_write_strobed(r, field_offs, d_set, strb);
    endaction
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

function Action field_write_access(Reg#(t) r, BlueCSRAccess_t access_type, Integer field_offs, Bit#(dw) d, Bit#(b__) strb)
    provisos(
        Bits#(t, st),
        Add#(st, a__, dw),
        Mul#(b__, 8, dw),
        Div#(dw, 8, b__)
    );
    action
        case(access_type)
            CSR_RW, CSR_WO: field_write_strobed(r, field_offs, d, strb);
            CSR_WC:         field_wc(r, field_offs, d, strb);
            CSR_WS:         field_ws(r, field_offs, d, strb);
            CSR_W1S:        field_w1s(r, field_offs, d, strb);
            CSR_W1C:        field_w1c(r, field_offs, d, strb);
            default:        noAction;
        endcase
    endaction
endfunction

function Integer bit_to_integer(Bit#(n) x);
    Integer res = 0;
    for (Integer i = 0; i < valueOf(n); i = i + 1)
        if(x[i] == 1)
            res = res + 2**i;
    return res;
endfunction

function Bool access_policy_allows(BlueCSRAccessPolicy_t policy, BlueCSRProt_t prot);
    return case (policy)
        CSR_ALLOW_ALL: True;
        CSR_SEC_SECURE_ONLY: (prot == CSR_SECURE);
        CSR_SEC_INSECURE_ONLY: (prot == CSR_INSECURE);
    endcase;
endfunction

function String integerToHexDigitS(Integer n) = charToString(integerToHexDigit(n));

function String integerToHex(Integer n);
    if(n < 16) return integerToHexDigitS(n);
    else return strConcat(integerToHex(n / 16), integerToHexDigitS(n % 16));
endfunction

function String csr_prefix_identifier(String prefix, String identifier);
    return prefix == "" ? identifier : prefix + "_" + identifier;
endfunction

function List#(RegMapEntry_t#(aw, dw)) csr_rebase_entry(Integer base, String prefix, RegMapEntry_t#(aw, dw) e);
    case(e) matches
        tagged RegMapDef       .entry: return Nil;
        tagged RegDef          .entry: begin let r = entry; r.offset = r.offset + base; r.identifier = csr_prefix_identifier(prefix, r.identifier); return Cons(tagged RegDef           r, Nil); end
        tagged RegRegionDef    .entry: begin let r = entry; r.offset = r.offset + base; r.identifier = csr_prefix_identifier(prefix, r.identifier); return Cons(tagged RegRegionDef     r, Nil); end
        tagged AccessPolicyDef .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged AccessPolicyDef  r, Nil); end
        tagged RegFieldDef     .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged RegFieldDef      r, Nil); end
        tagged ReadOpPure      .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged ReadOpPure       r, Nil); end
        tagged ReadOpAction    .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged ReadOpAction     r, Nil); end
        tagged WriteOp         .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged WriteOp          r, Nil); end
        tagged WriteOpAction   .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged WriteOpAction    r, Nil); end
        tagged ReadTrigger     .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged ReadTrigger      r, Nil); end
        tagged WriteTrigger    .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged WriteTrigger     r, Nil); end
        tagged ReadRegion      .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged ReadRegion       r, Nil); end
        tagged WriteRegion     .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged WriteRegion      r, Nil); end
        tagged ServerRegion    .entry: begin let r = entry; r.offset = r.offset + base;                                                             return Cons(tagged ServerRegion     r, Nil); end
        tagged RegBlockDef     .entry: begin let r = entry; r.offset = r.offset + base; r.prefix = csr_prefix_identifier(prefix, r.prefix);         return Cons(tagged RegBlockDef      r, Nil); end
        default                      : return Cons(e, Nil);
    endcase
endfunction

function Bool csr_entry_fits(Integer size, RegMapEntry_t#(aw, dw) e);
    Integer offs = 0;
    Integer len  = 0;
    case(e) matches
        tagged RegDef          .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged RegRegionDef    .entry: begin offs = entry.offset; len = entry.length;           end
        tagged AccessPolicyDef .entry: begin offs = entry.offset; len = entry.length;           end
        tagged RegFieldDef     .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged ReadOpPure      .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged ReadOpAction    .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged WriteOp         .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged WriteOpAction   .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged ReadTrigger     .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged WriteTrigger    .entry: begin offs = entry.offset; len = valueOf(TDiv#(dw, 8));  end
        tagged ReadRegion      .entry: begin offs = entry.offset; len = entry.length;           end
        tagged WriteRegion     .entry: begin offs = entry.offset; len = entry.length;           end
        tagged ServerRegion    .entry: begin offs = entry.offset; len = entry.length;           end
        tagged RegBlockDef     .entry: begin offs = entry.offset; len = entry.length;           end
    endcase
    return offs >= 0 && len >= 0 && (offs + len) <= size;
endfunction

module [BlueCSRCtx_t#(aw, dw)] csr_block#(Integer base, Integer size, String prefix, BlueCSRCtx_t#(aw, dw, i) child)(i);
    String label = "BlueCSR block " + prefix + ": ";
    //lift errors so discarded child interfaces cannot suppress them
    if(!is_power_of_two(size)) begin
        liftModule(errorM(label + "size must be a power of two."));
    end
    else if(base < 0 || (base + size) > 2 ** valueOf(aw)) begin
        liftModule(errorM(label + "range lies outside the CSR address space."));
    end
    else if((base % size) != 0) begin
        liftModule(errorM(label + "base must be aligned to size."));
    end

    let {ifc, entries} <- liftModule(getCollection(child));
    let map_defs = List::concat(List::map(get_regmap_def, entries));
    if(List::length(map_defs) > 1) begin
        liftModule(errorM(label + "child has more than one csr_regmap_def."));
    end
    for(Integer ei = 0; ei < List::length(entries); ei = ei + 1) begin
        if(!csr_entry_fits(size, entries[ei])) begin
            liftModule(errorM(label + "child entry lies outside [0, " + integerToString(size) + ")."));
        end
    end

    RegMapEntry_t#(aw, dw) block_entry = tagged RegBlockDef RegBlockDef_t {
        offset:      base,
        length:      size,
        prefix:      prefix,
        name:        List::isNull(map_defs) ? prefix : map_defs[0].name,
        description: List::isNull(map_defs) ? "" : map_defs[0].description
    };
    addToCollection(block_entry);
    List::mapM_(addToCollection, List::concat(List::map(csr_rebase_entry(base, prefix), entries)));
    RegMapEntry_t#(aw, dw) block_end = tagged RegBlockEnd;
    addToCollection(block_end);
    return ifc;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_regmap_def#(String name, String desc)();
    RegMapEntry_t#(aw, dw) entry = tagged RegMapDef RegMapDef_t {
        name: name,
        description: desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_def#(Integer offs, String ident, String desc)();
    Integer word_bytes    = valueOf(TDiv#(dw, 8));
    Integer address_space = 2 ** valueOf(aw);
    if(offs < 0 || (offs + word_bytes) > address_space) begin
        errorM("BlueCSR register " + ident + " lies outside the CSR address space.");
    end
    else if((offs % word_bytes) != 0) begin
        errorM("BlueCSR register " + ident + " offset must be aligned to the CSR word size.");
    end

    RegMapEntry_t#(aw, dw) entry = tagged RegDef RegDef_t {
        offset: offs,
        identifier: ident,
        description: desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_region_def#(Integer offs, Integer len, String ident, String desc)();
    Integer word_bytes    = valueOf(TDiv#(dw, 8));
    Integer address_space = 2 ** valueOf(aw);
    if(len <= 0) begin
        errorM("BlueCSR region " + ident + " has non-positive length.");
    end
    else if(offs < 0 || (offs + len) > address_space) begin
        errorM("BlueCSR region " + ident + " lies outside the CSR address space.");
    end
    else if(!is_power_of_two(len)) begin
        errorM("BlueCSR region " + ident + " length must be a power of two for mask-based address decoding.");
    end
    else if((offs % len) != 0) begin
        errorM("BlueCSR region " + ident + " offset must be aligned to its length for mask-based address decoding.");
    end
    else if((offs % word_bytes) != 0 || (len % word_bytes) != 0) begin
        errorM("BlueCSR region " + ident + " must contain an aligned, integer number of CSR words.");
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
        offset:  offs,
        length:  len,
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
        offset: offs,
        length: len,
        f_read: do_read
    };
    addToCollection(read_region_entry);
    RegMapEntry_t#(aw, dw) write_region_entry = tagged WriteRegion WriteRegion_t {
        offset:  offs,
        length:  len,
        f_write: do_write
    };
    addToCollection(write_region_entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_field_ops#(BlueCSRAccess_t access_type, Integer offs, t rv, Integer bitpos, function Bit#(dw) field_rd(), function Bit#(dw) field_const(), function Action write_field(BlueCSRAccess_t write_access, Bit#(dw) d, Bit#(TDiv#(dw, 8)) s), String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    if(bitpos < 0 || (bitpos + valueOf(sz_t)) > valueOf(dw)) begin
        errorM("BlueCSR field " + ident + " lies outside its register word.");
    end

    String reset_value = "0x" + integerToHex(bit_to_integer(pack(rv)));
    function Bit#(dw) do_read() = 0;
    function Action do_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) = noAction;

    case (access_type)
        CSR_RW: begin
            do_read = field_rd;
            do_write = write_field(CSR_RW);
        end
        CSR_RO: begin
            do_read = field_rd;
        end
        CSR_RC: begin
            do_read = field_const;
        end
        CSR_WO: begin
            do_write = write_field(CSR_WO);
        end
        CSR_WC: begin
            do_read = field_rd;
            do_write = write_field(CSR_WC);
        end
        CSR_WS: begin
            do_read = field_rd;
            do_write = write_field(CSR_WS);
        end
        CSR_W1S: begin
            do_read = field_rd;
            do_write = write_field(CSR_W1S);
        end
        CSR_W1C: begin
            do_read = field_rd;
            do_write = write_field(CSR_W1C);
        end
    endcase

    RegMapEntry_t#(aw, dw) read_entry  = tagged ReadOpPure ReadOpPure_t { offset: offs, f_read: do_read };
    RegMapEntry_t#(aw, dw) write_entry = tagged WriteOp WriteOp_t { offset: offs, f_write: do_write };
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

    if(access_type != CSR_WO) begin
        addToCollection(read_entry);
    end
    if(access_type != CSR_RO && access_type != CSR_RC) begin
        addToCollection(write_entry);
    end
    addToCollection(field_entry);
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

    function Bit#(dw) field_rd() = field_read_pure(r, bitpos);
    function Bit#(dw) field_const() = field_read_pure(rv, bitpos);
    function Action write_field(BlueCSRAccess_t write_access, Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) = field_write_access(r, write_access, bitpos, d, s);

    //populate operations based on access policy (unused ops get dropped)
    csr_reg_field_ops(access_type, offs, rv, bitpos, field_rd, field_const, write_field, ident, name, desc);

    return r;
endmodule

//shared implementation for fields whose state remains owned by BlueCSR
module [BlueCSRCtx_t#(aw, dw)] csr_reg_update#(BlueCSRAccess_t access_type, Integer offs, t rv, Integer bitpos, Maybe#(t) hw_update, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t)                           r                <- mkReg(rv);
    Wire#(Maybe#(t))                  w_hardware_upd   <- mkDWire(tagged Invalid);
    Wire#(Maybe#(CSRRegWrite_t#(dw))) w_software_write <- mkDWire(tagged Invalid);

    function Bit#(dw) field_rd() = field_read_pure(r, bitpos);
    function Bit#(dw) field_const() = field_read_pure(rv, bitpos);
    function Action write_field(BlueCSRAccess_t write_access, Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        action
            if(w_hardware_upd matches tagged Invalid) begin
                w_software_write <= tagged Valid CSRRegWrite_t {
                    data: d,
                    strobe: s
                };
            end
        endaction
    endfunction

    rule r_hw_upd if(hw_update matches tagged Valid .new_value);
        w_hardware_upd <= tagged Valid new_value;
    endrule

    //shared update rule to arbitrate HW and SW updates
    rule r_apply_update;
        if(w_hardware_upd matches tagged Valid .new_value) begin
            r <= new_value;
        end
        else if(w_software_write matches tagged Valid .write) begin
            field_write_access(r, access_type, bitpos, write.data, write.strobe);
        end
    endrule

    csr_reg_field_ops(access_type, offs, rv, bitpos, field_rd, field_const, write_field, ident, name, desc);
    
    return regToReadOnly(r);
endmodule

//read-write fields whose state may be updated by hardware. A same-cycle hardware update wins over a software write.
module [BlueCSRCtx_t#(aw, dw)] csr_reg_hu#(Integer offs, t rv, Integer bitpos, Maybe#(t) hw_update, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_update(CSR_RW, offs, rv, bitpos, hw_update, ident, name, desc);
    return r;
endmodule

//read-only fields whose state may be updated by hardware
module [BlueCSRCtx_t#(aw, dw)] csr_reg_ho#(Integer offs, t rv, Integer bitpos, Maybe#(t) hw_update, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_update(CSR_RO, offs, rv, bitpos, hw_update, ident, name, desc);
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

module [BlueCSRCtx_t#(aw, dw)] csr_reg_wo#(Integer offs, t rv, Integer bitpos, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t) r <- csr_reg_field(CSR_WO, offs, rv, bitpos, ident, name, desc);
    return regToReadOnly(r);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_w1c#(Integer offs, t rv, Integer bitpos, Maybe#(t) hw_update, String ident, String fname, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_update(CSR_W1C, offs, rv, bitpos, hw_update, ident, fname, desc);
    return r;
endmodule

//accumulator field whose state remains owned by BlueCSR. Every cycle with a Valid amount adds it (wrapping). A software write replaces the value and a same-cycle amount is added to the written value, so neither the write nor the event is lost (e.g. clearing a counter that counts every cycle).
module [BlueCSRCtx_t#(aw, dw)] csr_reg_accumulate_access#(BlueCSRAccess_t access_type, Integer offs, t rv, Integer bitpos, Maybe#(t) amount, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        Arith#(t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    Reg#(t)                           r                <- mkReg(rv);
    Wire#(Maybe#(CSRRegWrite_t#(dw))) w_software_write <- mkDWire(tagged Invalid);

    function Bit#(dw) field_rd() = field_read_pure(r, bitpos);
    function Bit#(dw) field_const() = field_read_pure(rv, bitpos);
    function Action write_field(BlueCSRAccess_t write_access, Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        action
            w_software_write <= tagged Valid CSRRegWrite_t { data: d, strobe: s };
        endaction
    endfunction

    (* fire_when_enabled, no_implicit_conditions *)
    rule r_accumulate (isValid(amount) || isValid(w_software_write));
        t value = r;
        if(w_software_write matches tagged Valid .write) value = field_value_strobed(value, bitpos, write.data, write.strobe);
        if(amount matches tagged Valid .a) value = value + a;
        r <= value;
    endrule

    csr_reg_field_ops(access_type, offs, rv, bitpos, field_rd, field_const, write_field, ident, name, desc);

    return regToReadOnly(r);
endmodule

//read-write accumulator: software may preset or clear, hardware adds amount
module [BlueCSRCtx_t#(aw, dw)] csr_reg_accumulate#(Integer offs, t rv, Integer bitpos, Maybe#(t) amount, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        Arith#(t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_accumulate_access(CSR_RW, offs, rv, bitpos, amount, ident, name, desc);
    return r;
endmodule

//read-write event counter: adds one in every cycle the event is True
module [BlueCSRCtx_t#(aw, dw)] csr_reg_counter#(Integer offs, t rv, Integer bitpos, Bool event_strobe, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        Arith#(t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_accumulate_access(CSR_RW, offs, rv, bitpos, event_strobe ? tagged Valid 1 : tagged Invalid, ident, name, desc);
    return r;
endmodule

//read-only event counter, owned by hardware
module [BlueCSRCtx_t#(aw, dw)] csr_reg_counter_ro#(Integer offs, t rv, Integer bitpos, Bool event_strobe, String ident, String name, String desc)(ReadOnly#(t))
    provisos(
        Bits#(t, sz_t),
        Arith#(t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_accumulate_access(CSR_RO, offs, rv, bitpos, event_strobe ? tagged Valid 1 : tagged Invalid, ident, name, desc);
    return r;
endmodule

//add one event-latched interrupt field. Software clears PENDING with W1C and controls ENABLE with RW. Multiple fields may contribute to the same line; create_blue_csr OR-composes their enabled pending states.
module [BlueCSRCtx_t#(aw, dw)] csr_irq#(Integer pending_offs, Integer enable_offs, Integer bitpos, Integer line, Bool event_strobe, String ident, String name, String desc)()
    provisos(
        Add#(1, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let rg_pending <- csr_reg_w1c(
        pending_offs,
        False,
        bitpos,
        (event_strobe ? tagged Valid True : tagged Invalid),
        ident,
        name,
        desc
    );
    let rg_enabled <- csr_reg_rw(
        enable_offs,
        False,
        bitpos,
        ident,
        name,
        "Enables " + name + "."
    );

    RegMapEntry_t#(aw, dw) irq_entry = tagged IRQSource IRQSource_t {
        line: line,
        active: rg_pending && rg_enabled
    };
    addToCollection(irq_entry);
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

//register action handlers own their state and consume/produce complete bus words. rv and bitpos describe the field for export; they do not mask data, allocate storage, or reset the callback's state. Each direction is exclusive.
module [BlueCSRCtx_t#(aw, dw)] csr_reg_act_ops#(BlueCSRAccess_t access_type, Integer offs, t rv, Integer bitpos, Bool can_read, BlueCSR_Rsp_t#(dw) unavailable_rsp, function ActionValue#(BlueCSR_Rsp_t#(dw)) read_fn(), function Bool can_write(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb), BlueCSRResponse_t unavailable_resp, function ActionValue#(BlueCSRResponse_t) write_fn(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb), String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, unused_width, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    if(access_type != CSR_RO && access_type != CSR_WO && access_type != CSR_RW) begin
        errorM("BlueCSR action field " + ident + " requires RO, WO, or RW access.");
    end
    if(bitpos < 0 || valueOf(sz_t) <= 0 || (bitpos + valueOf(sz_t)) > valueOf(dw)) begin
        errorM("BlueCSR action field " + ident + " lies outside its register word.");
    end

    function Bool read_available() = can_read;

    if(access_type != CSR_WO) begin
        RegMapEntry_t#(aw, dw) read_entry = tagged ReadOpAction ReadOpAction_t {
            offset:          offs,
            exclusive:       True,
            can_read:        read_available,
            unavailable_rsp: unavailable_rsp,
            f_read:          read_fn
        };
        addToCollection(read_entry);
    end
    if(access_type != CSR_RO) begin
        RegMapEntry_t#(aw, dw) write_entry = tagged WriteOpAction WriteOpAction_t {
            offset:           offs,
            exclusive:        True,
            can_write:        can_write,
            unavailable_resp: unavailable_resp,
            f_write:          write_fn
        };
        addToCollection(write_entry);
    end
    RegMapEntry_t#(aw, dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset:      offs,
        identifier:  ident,
        name:        name,
        description: desc,
        access_type: access_type,
        bit_offset:  bitpos,
        width:       valueOf(sz_t),
        reset_value: "0x" + integerToHex(bit_to_integer(pack(rv)))
    };
    addToCollection(field_entry);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_act_ro#(Integer offs, t rv, Integer bitpos, Bool can_read, BlueCSR_Rsp_t#(dw) unavailable_rsp, function ActionValue#(BlueCSR_Rsp_t#(dw)) read_fn(), String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, unused_width, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    function Bool can_write(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb) = False;
    function ActionValue#(BlueCSRResponse_t) write_fn(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb);
        actionvalue
            return CSR_DECERR;
        endactionvalue
    endfunction
    csr_reg_act_ops(CSR_RO, offs, rv, bitpos, can_read, unavailable_rsp, read_fn, can_write, CSR_DECERR, write_fn, ident, name, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_act_wo#(Integer offs, t rv, Integer bitpos, function Bool can_write(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb), BlueCSRResponse_t unavailable_resp, function ActionValue#(BlueCSRResponse_t) write_fn(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb), String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, unused_width, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    BlueCSR_Rsp_t#(dw) unavailable_rsp = BlueCSR_Rsp_t { rdata: 0, resp: CSR_DECERR };
    function ActionValue#(BlueCSR_Rsp_t#(dw)) read_fn();
        actionvalue
            return unavailable_rsp;
        endactionvalue
    endfunction
    csr_reg_act_ops(CSR_WO, offs, rv, bitpos, False, unavailable_rsp, read_fn, can_write, unavailable_resp, write_fn, ident, name, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_act_rw#(Integer offs, t rv, Integer bitpos, Bool can_read, BlueCSR_Rsp_t#(dw) unavailable_rsp, function ActionValue#(BlueCSR_Rsp_t#(dw)) read_fn(), function Bool can_write(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb), BlueCSRResponse_t unavailable_resp, function ActionValue#(BlueCSRResponse_t) write_fn(Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb), String ident, String name, String desc)()
    provisos(
        Bits#(t, sz_t),
        Add#(sz_t, unused_width, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    csr_reg_act_ops(CSR_RW, offs, rv, bitpos, can_read, unavailable_rsp, read_fn, can_write, unavailable_resp, write_fn, ident, name, desc);
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
        offset:          offs,
        exclusive:       True,
        can_read:        can_read,
        unavailable_rsp: BlueCSR_Rsp_t { rdata: 0, resp: CSR_SLVERR },
        f_read:          do_read
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
        offset:          offs,
        exclusive:       False,
        can_read:        can_read,
        unavailable_rsp: BlueCSR_Rsp_t { rdata: 0, resp: CSR_OKAY },
        f_read:          do_read
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
    Bit#(TDiv#(sz_t, 8)) fifo_strobes     = unpack(-1);
    Bit#(TDiv#(dw, 8))   required_strobes = zeroExtend(fifo_strobes);

    function Bool can_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        return (s != required_strobes) || fifo.notFull;
    endfunction

    function ActionValue#(BlueCSRResponse_t) do_write(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        actionvalue
            if(s == required_strobes) begin
                fifo.enq(unpack(truncate(d)));
            end
            return (s == required_strobes) ? CSR_OKAY : CSR_SLVERR;
        endactionvalue
    endfunction

    RegMapEntry_t#(aw, dw) write_entry = tagged WriteOpAction WriteOpAction_t {
        offset:           offs,
        exclusive:        True,
        can_write:        can_write,
        unavailable_resp: CSR_SLVERR,
        f_write:          do_write
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
        offset: offs,
        length: len,
        f_read: do_read
    };
    addToCollection(read_region_entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

/*
 * Region served by a request/response server, e.g. a BRAM. Requests carry the byte address relative to offs,
 * data, strobes and protection unchanged; the server returns exactly one response per request, in order, after
 * any latency. Further requests to the map wait for that response. While can_access is False, accesses return
 * unavailable_resp without reaching the server.
 */
module [BlueCSRCtx_t#(aw, dw)] csr_region_server#(Integer offs, Integer len, Bool can_access, BlueCSRResponse_t unavailable_resp, Server#(BlueCSR_Req_t#(aw, dw), BlueCSR_Rsp_t#(dw)) server, String ident, String desc)();
    RegMapEntry_t#(aw, dw) entry = tagged ServerRegion ServerRegion_t {
        offset:           offs,
        length:           len,
        can_access:       can_access,
        unavailable_resp: unavailable_resp,
        server:           server
    };
    addToCollection(entry);
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

/*
 * Region backed by a standard BRAM server port (BRAM1Port.portA, BRAM2Port.portA/B), one element per CSR word.
 * The element sits at bit 0 of the word. A write needs the strobes of every byte the element occupies; no strobes
 * make it a no-op, partial strobes return CSR_SLVERR. The BRAM is used with responseOnWrite False.
 */
module [BlueCSRCtx_t#(aw, dw)] csr_region_bram#(Integer offs, Integer len, Bool can_access, BlueCSRResponse_t unavailable_resp, BRAMServer#(addr_t, t) bram, String ident, String desc)()
    provisos(
        Bits#(addr_t, addr_w),
        Bits#(t, t_w),
        Add#(t_w, a__, dw)
    );
    Integer t_bytes  = (valueOf(t_w) + 7) / 8;
    Integer word_lsb = log2(valueOf(TDiv#(dw, 8)));

    FIFOF#(Maybe#(BlueCSRResponse_t)) f_pending <- mkSizedFIFOF(1);

    Server#(BlueCSR_Req_t#(aw, dw), BlueCSR_Rsp_t#(dw)) server = interface Server;
        interface Put request;
            method Action put(BlueCSR_Req_t#(aw, dw) req);
                Bit#(TDiv#(dw, 8)) element_strb = fromInteger(2 ** t_bytes - 1);
                Bool               full         = (req.wstrb & element_strb) == element_strb;
                Bool               none         = (req.wstrb & element_strb) == 0;
                addr_t             address      = unpack(cExtend(req.addr >> word_lsb));
                if(!req.wr) begin
                    bram.request.put(BRAMRequest { write: False, responseOnWrite: False, address: address, datain: ? });
                    f_pending.enq(tagged Invalid);
                end
                else begin
                    if(full) bram.request.put(BRAMRequest { write: True, responseOnWrite: False, address: address, datain: unpack(truncate(req.wdata)) });
                    f_pending.enq(tagged Valid (full || none ? CSR_OKAY : CSR_SLVERR));
                end
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(BlueCSR_Rsp_t#(dw)) get;
                f_pending.deq;
                if(f_pending.first matches tagged Valid .resp)
                    return BlueCSR_Rsp_t { rdata: 0, resp: resp };
                else begin
                    let x <- bram.response.get;
                    return BlueCSR_Rsp_t { rdata: zeroExtend(pack(x)), resp: CSR_OKAY };
                end
            endmethod
        endinterface
    endinterface;

    csr_region_server(offs, len, can_access, unavailable_resp, server, ident, desc);
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trig#(Integer offs, Bool delay, BlueCSRTrigger_t rw)(Reg#(Bit#(1)))
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
        RegMapEntry_t#(aw, dw) entry = tagged ReadTrigger ReadTrigger_t { offset: offs, delay: delay, trigger: f_trigger };
        addToCollection(entry);
    end if(rw == TRIG_WO || rw == TRIG_RW) begin
        RegMapEntry_t#(aw, dw) entry = tagged WriteTrigger WriteTrigger_t { offset: offs, delay: delay, trigger: f_trigger };
        addToCollection(entry);
    end
    return rg_trig;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trigr#(Integer offs, Bool delay)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_trig(offs, delay, TRIG_RO);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trigw#(Integer offs, Bool delay)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_trig(offs, delay, TRIG_WO);
    return r;
endmodule

module [BlueCSRCtx_t#(aw, dw)] csr_reg_trigrw#(Integer offs, Bool delay)(Reg#(Bit#(1)))
    provisos(
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );
    let r <- csr_reg_trig(offs, delay, TRIG_RW);
    return r;
endmodule

function List#(ReadOpPure_t#(dw)) find_pure_reads_by_offs(List#(ReadOpPure_t#(dw)) l, Integer offs);
    function Bool p(ReadOpPure_t#(dw) read_op) = read_op.offset == offs;
    return List::filter(p, l);
endfunction

function List#(ReadOpAction_t#(dw)) find_action_reads_by_offs(List#(ReadOpAction_t#(dw)) l, Integer offs);
    function Bool p(ReadOpAction_t#(dw) read_op) = read_op.offset == offs;
    return List::filter(p, l);
endfunction

function List#(AccessPolicyDef_t) find_policies_by_offs(List#(AccessPolicyDef_t) l, Integer offs, Integer len);
    function Bool p(AccessPolicyDef_t pol_def) = pol_def.offset == offs && pol_def.length == len;
    return List::filter(p, l);
endfunction

function List#(WriteOp_t#(dw)) find_write_ops_by_offs(List#(WriteOp_t#(dw)) l, Integer offs);
    function Bool p(WriteOp_t#(dw) write_op) = write_op.offset == offs;
    return List::filter(p, l);
endfunction

function List#(WriteOpAction_t#(dw)) find_action_writes_by_offs(List#(WriteOpAction_t#(dw)) l, Integer offs);
    function Bool p(WriteOpAction_t#(dw) write_op) = write_op.offset == offs;
    return List::filter(p, l);
endfunction

function List#(ReadTrigger_t) find_rtrig_by_offs(List#(ReadTrigger_t) l, Integer offs);
    function Bool p(ReadTrigger_t rtrig) = rtrig.offset == offs;
    return List::filter(p, l);
endfunction

function List#(WriteTrigger_t) find_wtrig_by_offs(List#(WriteTrigger_t) l, Integer offs);
    function Bool p(WriteTrigger_t wtrig) = wtrig.offset == offs;
    return List::filter(p, l);
endfunction

function List#(ReadRegion_t#(aw, dw)) find_read_regions_by_range(List#(ReadRegion_t#(aw, dw)) l, Integer offs, Integer len);
    function Bool p(ReadRegion_t#(aw, dw) read_op) = read_op.offset == offs && read_op.length == len;
    return List::filter(p, l);
endfunction

function List#(WriteRegion_t#(aw, dw)) find_write_regions_by_range(List#(WriteRegion_t#(aw, dw)) l, Integer offs, Integer len);
    function Bool p(WriteRegion_t#(aw, dw) write_op) = write_op.offset == offs && write_op.length == len;
    return List::filter(p, l);
endfunction

interface BusAccess_ifc#(type ext_ifc, type int_ifc);
    interface ext_ifc external;
    interface int_ifc internal;
endinterface

typedef BusAccess_ifc#(BlueCSR_Fab_ifc#(aw, dw), int_ifc)   BlueCSRAccess_Fab_ifc#(numeric type aw, numeric type dw, type int_ifc);
typedef BusAccess_ifc#(BlueCSR_ifc#(aw, dw, ni), int_ifc)   BlueCSRAccess_ifc#(numeric type aw, numeric type dw, numeric type ni, type int_ifc);

//buffer_in: requests are registered before decode; buffer_out: responses are registered, so no
//combinational path runs from the request through decode to the consumer; both add one cycle
typedef struct {
    Bool              buffer_in;
    Bool              buffer_out;
    BlueCSRResponse_t default_response;
} BlueCSRCfg_t deriving(Bits, Eq, FShow);

instance DefaultValue#(BlueCSRCfg_t);
    defaultValue = BlueCSRCfg_t { buffer_in: False, buffer_out: False, default_response: CSR_DECERR };
endinstance

module [Module] create_blue_csr_cfg#(BlueCSRCtx_t#(aw, dw, i) ctx, BlueCSRCfg_t cfg)(BlueCSRAccess_ifc#(aw, dw, ni, i));
    Bool              buffer_in        = cfg.buffer_in;
    BlueCSRResponse_t default_response = cfg.default_response;

    let {coll_device_ifc, c} <- getCollection(ctx);
    let validation = validate_blue_csr_entries(c);
    if(!validation.valid) begin
        errorM(validation.errors);
    end

    let regdefs         = List::concat(List::map(get_reg_def, c));
    let regiondefs      = List::concat(List::map(get_reg_region_def, c));
    let access_policies = List::concat(List::map(get_access_policy_def, c));
    let value_reads     = List::concat(List::map(get_pure_read, c));
    let action_reads    = List::concat(List::map(get_action_read, c));
    let read_regions    = List::concat(List::map(get_read_region, c));
    let write_ops       = List::concat(List::map(get_write_op, c));
    let action_writes   = List::concat(List::map(get_action_write, c));
    let write_regions   = List::concat(List::map(get_write_region, c));
    let server_regions  = List::concat(List::map(get_server_region, c));
    let read_triggers   = List::concat(List::map(get_read_trigger, c));
    let write_triggers  = List::concat(List::map(get_write_trigger, c));
    let irq_sources     = List::concat(List::map(get_irq_source, c));

    Integer word_bytes = valueOf(TDiv#(dw, 8));

    for (Integer i = 0; i < List::length(irq_sources); i = i + 1) begin
        let irq = irq_sources[i];
        if(irq.line < 0 || irq.line >= valueOf(ni)) begin
            errorM("BlueCSR IRQ line " + integerToString(irq.line) + " lies outside the configured " + integerToString(valueOf(ni)) + "-line vector.");
        end
    end

    FIFOF#(BlueCSR_Req_t#(aw, dw))  f_req;
    FIFOF#(BlueCSR_Rsp_t#(dw))      f_rsp;
    if(cfg.buffer_out)
        f_rsp <- mkFIFOF;
    else
        f_rsp <- mkBypassFIFOF;

    //the requests are still buffered with the bypass fifo 
    //but only when there is no space in the output. Otherwise, the
    //request is processed combinationally
    if(!buffer_in)
        f_req <- mkBypassFIFOF;
    else
        f_req <- mkSizedFIFOF(1);

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

    function Action dispatch_read_triggers(List#(ReadTrigger_t) l);
        function Action fold_trigger(Action acc, ReadTrigger_t op);
            return action
                acc;
                op.trigger;
            endaction;
        endfunction
        return List::foldl(fold_trigger, noAction, l);
    endfunction

    function Action dispatch_write_triggers(List#(WriteTrigger_t) l);
        function Action fold_trigger(Action acc, WriteTrigger_t op);
            return action
                acc;
                op.trigger;
            endaction;
        endfunction
        return List::foldl(fold_trigger, noAction, l);
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

    Rules read_rules  = emptyRules;
    Rules write_rules = emptyRules;

    for (Integer i = 0; i < List::length(regdefs); i = i + 1) begin
        let field_values    = find_pure_reads_by_offs(value_reads, regdefs[i].offset);
        let field_actions   = find_action_reads_by_offs(action_reads, regdefs[i].offset);
        let rtrigs          = find_rtrig_by_offs(read_triggers, regdefs[i].offset);
        let wtrigs          = find_wtrig_by_offs(write_triggers, regdefs[i].offset);
        let reg_policies    = find_policies_by_offs(access_policies, regdefs[i].offset, word_bytes);
        let reg_writes      = find_write_ops_by_offs(write_ops, regdefs[i].offset);
        let write_actions   = find_action_writes_by_offs(action_writes, regdefs[i].offset);

        if(List::length(field_actions) > 1) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has multiple action reads.");
        end
        if((List::length(field_actions) == 1) && field_actions[0].exclusive && (List::length(field_values) > 0)) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has an exclusive action read mixed with value reads.");
        end
        if(List::length(write_actions) > 1) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has multiple action writes.");
        end
        if((List::length(write_actions) == 1) && write_actions[0].exclusive && (List::length(reg_writes) > 0)) begin
            errorM("BlueCSR register at offset 0x" + integerToHex(regdefs[i].offset) + " has an exclusive action write mixed with other writes.");
        end

        let read_policy     = List::length(reg_policies) > 0 ? reg_policies[0].read_policy : CSR_ALLOW_ALL;
        let write_policy    = List::length(reg_policies) > 0 ? reg_policies[0].write_policy : CSR_ALLOW_ALL;

        let req             = f_req.first;
        let req_hit         = (req.addr == fromInteger(regdefs[i].offset));
        let req_rd_allowed  = access_policy_allows(read_policy,  req.prot);
        let req_wr_allowed  = access_policy_allows(write_policy, req.prot);

        //TODO: should triggers align with data output? (difficult as it moves through arbitrarily delayed FIFOs)

        if(List::length(field_actions) == 0) begin
            if((List::length(field_values) > 0) || (List::length(rtrigs) > 0)) begin
                read_rules = rJoinMutuallyExclusive(rules
                    rule rread_reg_allow(!req.wr && req_hit && req_rd_allowed);
                        f_rsp.enq(
                            BlueCSR_Rsp_t {
                                rdata:  combine_reads(field_values),
                                resp:   CSR_OKAY
                            }
                        );
                        dispatch_read_triggers(rtrigs);
                        f_req.deq;
                    endrule
                endrules, read_rules);
            end
        end
        else begin
            read_rules = rJoinMutuallyExclusive(rules
                //only the selected callback branch needs its method guards
                (* aggressive_implicit_conditions *)
                rule rread_reg_action_available(!req.wr && req_hit && req_rd_allowed && field_actions[0].can_read);
                    let action_rsp <- field_actions[0].f_read;
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata:  combine_reads(field_values) | action_rsp.rdata,
                            resp:   action_rsp.resp
                        }
                    );
                    dispatch_read_triggers(rtrigs);
                    f_req.deq;
                endrule
                rule rread_reg_action_unavailable(!req.wr && req_hit && req_rd_allowed && !field_actions[0].can_read);
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata: combine_reads(field_values) | field_actions[0].unavailable_rsp.rdata,
                            resp: field_actions[0].unavailable_rsp.resp
                        }
                    );
                    dispatch_read_triggers(rtrigs);
                    f_req.deq;
                endrule
            endrules, read_rules);
        end

        if(List::length(write_actions) == 0) begin
            if((List::length(reg_writes) > 0) || (List::length(wtrigs) > 0)) begin
                write_rules = rJoinMutuallyExclusive(rules
                    rule rwrite_reg_allow(req.wr && req_hit && req_wr_allowed);
                        dispatch_reg_writes(reg_writes, req.wdata, req.wstrb);
                        f_rsp.enq(
                            BlueCSR_Rsp_t {
                                rdata:  0,
                                resp:   CSR_OKAY
                            }
                        );
                        dispatch_write_triggers(wtrigs);
                        f_req.deq;
                    endrule
                endrules, write_rules);
            end
        end
        else begin
            write_rules = rJoinMutuallyExclusive(rules
                //preserve conditional method guards in write callbacks
                (* aggressive_implicit_conditions *)
                rule rwrite_reg_action_available(req.wr && req_hit && req_wr_allowed && write_actions[0].can_write(req.wdata, req.wstrb));
                    let action_resp <- write_actions[0].f_write(req.wdata, req.wstrb);
                    if(action_resp == CSR_OKAY || action_resp == CSR_EXOKAY) begin
                        dispatch_reg_writes(reg_writes, req.wdata, req.wstrb);
                    end
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata: 0,
                            resp: action_resp
                        }
                    );
                    dispatch_write_triggers(wtrigs);
                    f_req.deq;
                endrule
                rule rwrite_reg_action_unavailable(req.wr && req_hit && req_wr_allowed && !write_actions[0].can_write(req.wdata, req.wstrb));
                    f_rsp.enq(
                        BlueCSR_Rsp_t {
                            rdata: 0,
                            resp: write_actions[0].unavailable_resp
                        }
                    );
                    dispatch_write_triggers(wtrigs);
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

        if(List::length(region_reads) > 0) begin
            read_rules = rJoinMutuallyExclusive(rules
            rule rread_region_allow(!req.wr && req_hit && req_aligned && req_rd_allowed);
                Bit#(dw) read_data = region_reads[0].f_read(local_addr);
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  read_data,
                        resp:   CSR_OKAY
                    }
                );
                f_req.deq;
            endrule
            endrules, read_rules);
        end

        if(List::length(region_writes) > 0) begin
            write_rules = rJoinMutuallyExclusive(rules
            rule rwrite_region_allow(req.wr && req_hit && req_aligned && req_wr_valid && req_wr_allowed);
                region_writes[0].f_write(local_addr, req.wdata);
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  0,
                        resp:   CSR_OKAY
                    }
                );
                f_req.deq;
                //region writes are only allowed for fully enabled strobes
            endrule
            endrules, write_rules);
        end
    end

    //a server access holds its request in f_req until the response returns, so no other rule can match it
    Bool server_busy = False;
    for (Integer i = 0; i < List::length(server_regions); i = i + 1) begin
        let region          = server_regions[i];
        let region_policies = find_policies_by_offs(access_policies, region.offset, region.length);
        let read_policy     = List::length(region_policies) > 0 ? region_policies[0].read_policy : CSR_ALLOW_ALL;
        let write_policy    = List::length(region_policies) > 0 ? region_policies[0].write_policy : CSR_ALLOW_ALL;

        Reg#(Bool) rg_waiting <- mkReg(False);
        server_busy = server_busy || rg_waiting;

        let req             = f_req.first;
        let local_req       = req;
        local_req.addr      = req.addr - fromInteger(region.offset);
        let req_hit         = is_region_addr(req.addr, region.offset, region.length) && is_word_aligned(req.addr);
        let req_rd_allowed  = access_policy_allows(read_policy,  req.prot);
        let req_wr_allowed  = access_policy_allows(write_policy, req.prot);

        //reads and writes join the rule group of their direction, like registers and regions above
        function Rules server_rules(Bool dir_hit) = rules
            //servers may call their own subcomponents conditionally
            (* aggressive_implicit_conditions *)
            rule rserver_region_request(!rg_waiting && dir_hit && region.can_access);
                region.server.request.put(local_req);
                rg_waiting <= True;
            endrule
            rule rserver_region_unavailable(!rg_waiting && dir_hit && !region.can_access);
                f_rsp.enq(BlueCSR_Rsp_t { rdata: 0, resp: region.unavailable_resp });
                f_req.deq;
            endrule
            //the request stays at the head of f_req until its response returns
            (* aggressive_implicit_conditions *)
            rule rserver_region_response(rg_waiting && dir_hit);
                let rsp <- region.server.response.get;
                f_rsp.enq(rsp);
                f_req.deq;
                rg_waiting <= False;
            endrule
        endrules;

        read_rules  = rJoinMutuallyExclusive(server_rules(!req.wr && req_hit && req_rd_allowed), read_rules);
        write_rules = rJoinMutuallyExclusive(server_rules(req.wr && req_hit && req_wr_allowed), write_rules);
    end

    read_rules = rJoinDescendingUrgency(read_rules,
        rules
            rule rread_default(!f_req.first.wr && !server_busy); //only fires if a request is available
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  0,
                        resp:   default_response
                    }
                );
                f_req.deq;
            endrule
        endrules
    );

    write_rules = rJoinDescendingUrgency(write_rules,
        rules
            rule rwrite_default(f_req.first.wr && !server_busy);
                f_rsp.enq(
                    BlueCSR_Rsp_t {
                        rdata:  0,
                        resp:   default_response
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

        method Vector#(ni, Bool) irqs;
            Vector#(ni, Bool) result = replicate(False);
            for (Integer i = 0; i < List::length(irq_sources); i = i + 1) begin
                let irq = irq_sources[i];
                if(irq.line >= 0 && irq.line < valueOf(ni)) begin
                    result[irq.line] = result[irq.line] || irq.active;
                end
            end
            return result;
        endmethod
    endinterface

    interface internal = coll_device_ifc;
endmodule

module [Module] create_blue_csr_with_default_response#(
    BlueCSRCtx_t#(aw, dw, i) ctx,
    Bool buffer_in,
    BlueCSRResponse_t default_response
)(BlueCSRAccess_ifc#(aw, dw, ni, i));
    let csr <- create_blue_csr_cfg(ctx, BlueCSRCfg_t { buffer_in: buffer_in, buffer_out: False, default_response: default_response });
    return csr;
endmodule

module [Module] create_blue_csr#(BlueCSRCtx_t#(aw, dw, i) ctx, Bool buffer_in)(BlueCSRAccess_ifc#(aw, dw, ni, i));
    let csr <- create_blue_csr_cfg(ctx, BlueCSRCfg_t { buffer_in: buffer_in, buffer_out: False, default_response: CSR_DECERR });
    return csr;
endmodule

endpackage
