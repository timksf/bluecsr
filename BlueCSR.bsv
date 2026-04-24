package BlueCSR;

import List :: *;
import BUtils :: *;
import ModuleCollect :: *;
import Vector :: *;

typedef enum {
    CSR_OKAY = 2'b00,
    CSR_EXOKAY = 2'b01,
    CSR_SLVERR = 2'b10,
    CSR_DECERR = 2'b11
} BlueCSRResponse_t deriving(Bits, Eq, FShow);

typedef enum {
    CSR_SECURE = 1'b0,
    CSR_INSECURE = 1'b1
} BlueCSRProt_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(dw) data;
    BlueCSRResponse_t resp;
} BlueCSRReadRs_t#(numeric type dw) deriving(Bits, Eq, FShow);

typedef struct {
    BlueCSRResponse_t resp;
} BlueCSRWriteRs_t deriving(Bits, Eq, FShow);

typedef enum {
    CSR_ALLOW_ALL,
    CSR_SEC_SECURE_ONLY,
    CSR_SEC_INSECURE_ONLY
} AccessPolicy_t deriving(Bits, Eq, FShow);

interface BlueCSR_ifc#(numeric type aw, numeric type dw);
    method ActionValue#(BlueCSRWriteRs_t) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe, BlueCSRProt_t prot);
    method Action write_strobed(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe);
    (* always_ready *)
    method BlueCSRReadRs_t#(dw) read(Bit#(aw) addr, BlueCSRProt_t prot);
    (* always_ready *)
    method Bit#(dw) read_pure(Bit#(aw) addr);
    method ActionValue#(Bit#(dw)) read_impure(Bit#(aw) addr);
endinterface

typedef ModuleCollect#(RegMapEntry_t#(dw), ifc) BlueCSRCtx_t#(numeric type dw, type ifc);

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
    AccessPolicy_t read_policy;
    AccessPolicy_t write_policy;
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
    function Bit#(dw) _(Bit#(aw) a) f_read;
} ReadOpPure_t#(numeric type dw);

typedef struct {
    Integer offs;
    function ActionValue#(Bit#(dw)) _(Bit#(aw) a) f_read;
} ReadOpImpure_t#(numeric type dw);

typedef struct {
    Integer offs;
    function Action _(Bit#(aw) a, Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) f_write;
} WriteOp_t#(numeric type dw);

typedef struct {
    Integer offs;
    Integer length;
    function Bit#(dw) _(Bit#(dw) a) f_read;
} ReadRegionPure_t#(numeric type dw);

typedef struct {
    Integer offs;
    Integer length;
    function Action _(Bit#(dw) a, Bit#(dw) d) f_write;
} WriteRegion_t#(numeric type dw);

typedef union tagged {
    RegMapDef_t             RegMapDef;
    RegDef_t                RegDef;
    RegRegionDef_t          RegRegionDef;
    AccessPolicyDef_t       AccessPolicyDef;
    RegFieldDef_t           RegFieldDef;
    ReadOpPure_t#(dw)       ReadOpPure;
    ReadOpImpure_t#(dw)     ReadOpImpure;
    WriteOp_t#(dw)          WriteOp;
    ReadRegionPure_t#(dw)   ReadRegionPure;
    WriteRegion_t#(dw)      WriteRegion;
} RegMapEntry_t#(numeric type dw);

function List#(ReadOpPure_t#(dw))       get_pure_read           (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged ReadOpPure        .rr ? Cons(rr, Nil) : Nil;
function List#(ReadOpImpure_t#(dw))     get_impure_read         (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged ReadOpImpure      .rr ? Cons(rr, Nil) : Nil;
function List#(WriteOp_t#(dw))          get_write_op            (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged WriteOp           .rr ? Cons(rr, Nil) : Nil;
function List#(ReadRegionPure_t#(dw))   get_pure_read_region    (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged ReadRegionPure    .rr ? Cons(rr, Nil) : Nil;
function List#(WriteRegion_t#(dw))      get_write_region        (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged WriteRegion       .rr ? Cons(rr, Nil) : Nil;
function List#(AccessPolicyDef_t)       get_access_policy_def   (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged AccessPolicyDef   .rr ? Cons(rr, Nil) : Nil;
function List#(RegFieldDef_t)           get_regfield_def        (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged RegFieldDef       .rr ? Cons(rr, Nil) : Nil;
function List#(RegDef_t)                get_reg_def             (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged RegDef            .rr ? Cons(rr, Nil) : Nil;
function List#(RegRegionDef_t)          get_reg_region_def      (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged RegRegionDef      .rr ? Cons(rr, Nil) : Nil;
function List#(RegMapDef_t)             get_regmap_def          (RegMapEntry_t#(dw) regmap_entry) = regmap_entry matches tagged RegMapDef         .rr ? Cons(rr, Nil) : Nil;

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

function ActionValue#(Bit#(dw)) field_read_impure(Reg#(t) r, Integer field_offs) 
    provisos(
        Bits#(t, st),
        FieldReadPure#(t, dw)
    );
    actionvalue
        return field_read_pure(r, field_offs);
    endactionvalue
endfunction

function Integer bit_to_integer(Bit#(n) x);
    Integer res = 0;
    for (Integer i = 0; i < valueOf(n); i = i + 1)
        if(x[i] == 1)
            res = res + 2**i;
    return res;
endfunction

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
        for(Integer i = 0; i < valueOf(b__); i = i + 1) begin
            if(unpack(strobe[i])) begin
                cur_bytes[i] = wr_bytes[i];
            end
        end
        Bit#(dw) merged_word = pack(cur_bytes);
        Bit#(st) new_field = truncate(merged_word >> fromInteger(field_offs));
        r <= unpack(new_field);
    endaction
endfunction

function String append_validation_error(String acc, String msg);
    if(acc == "") return msg;
    else return acc + "\n" + msg;
endfunction

function Bool access_policy_allows(AccessPolicy_t policy, BlueCSRProt_t prot);
    return case (policy)
        CSR_ALLOW_ALL:          True;
        CSR_SEC_SECURE_ONLY:    (prot == CSR_SECURE);
        CSR_SEC_INSECURE_ONLY:  (prot == CSR_INSECURE);
    endcase;
endfunction

function BlueCSRReadRs_t#(dw) bluecsr_read_resp(Bit#(dw) data, BlueCSRResponse_t resp);
    return BlueCSRReadRs_t {
        data: data,
        resp: resp
    };
endfunction

function BlueCSRWriteRs_t bluecsr_write_resp(BlueCSRResponse_t resp);
    return BlueCSRWriteRs_t {
        resp: resp
    };
endfunction

function Integer count_regdefs_at(List#(RegDef_t) regdefs, Integer offs);
    Integer count = 0;
    for(Integer i = 0; i < length(regdefs); i = i + 1) begin
        if(regdefs[i].offset == offs) begin
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
    for(Integer i = 0; i < length(regions); i = i + 1) begin
        if((regions[i].offset == offs) && (regions[i].length == len)) begin
            count = count + 1;
        end
    end
    return count;
endfunction

function Integer count_access_policies_exact(List#(AccessPolicyDef_t) policies, Integer offs, Integer len);
    Integer count = 0;
    for(Integer i = 0; i < length(policies); i = i + 1) begin
        if((policies[i].offset == offs) && (policies[i].length == len)) begin
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

function RegMapValidation_t validate_blue_csr_entries(List#(RegMapEntry_t#(dw)) c);
    let regmap_defs         = List::concat(List::map(get_regmap_def, c));
    let regdefs             = List::concat(List::map(get_reg_def, c));
    let regiondefs          = List::concat(List::map(get_reg_region_def, c));
    let access_policies     = List::concat(List::map(get_access_policy_def, c));
    let regfields           = List::concat(List::map(get_regfield_def, c));
    let pure_reads          = List::concat(List::map(get_pure_read, c));
    let impure_reads        = List::concat(List::map(get_impure_read, c));
    let writes              = List::concat(List::map(get_write_op, c));
    let pure_read_regions   = List::concat(List::map(get_pure_read_region, c));
    let write_regions       = List::concat(List::map(get_write_region, c));

    Integer word_bytes = valueOf(TDiv#(dw, 8));

    String errors = "";
    String map_name = "BlueCSR";
    String map_description = "";

    if(length(regmap_defs) == 0) begin
        errors = append_validation_error(errors, "BlueCSR validation failed: exactly one csr_regmap_def is required, found none.");
    end
    else if(length(regmap_defs) > 1) begin
        errors = append_validation_error(errors, "BlueCSR validation failed: exactly one csr_regmap_def is required, found " + integerToString(length(regmap_defs)) + ".");
    end
    else begin
        map_name = regmap_defs[0].name;
        map_description = regmap_defs[0].description;
    end

    for(Integer ri = 0; ri < length(regdefs); ri = ri + 1) begin
        let rd = regdefs[ri];
        if(count_regdefs_at(regdefs, rd.offset) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: register offset 0x" + integerToString(rd.offset) + " is defined multiple times.");
        end
    end

    for(Integer ri = 0; ri < length(regiondefs); ri = ri + 1) begin
        let region = regiondefs[ri];
        if(count_regions_exact(regiondefs, region.offset, region.length) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: region " + region.identifier + " is defined multiple times.");
        end
        if(region.length <= 0) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: region " + region.identifier + " has non-positive length.");
        end
        if((region.offset % word_bytes) != 0) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: region " + region.identifier + " offset is not aligned to the CSR word size.");
        end
        if((region.length % word_bytes) != 0) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: region " + region.identifier + " length is not an integer number of CSR words.");
        end
        for(Integer rj = ri + 1; rj < length(regiondefs); rj = rj + 1) begin
            let other = regiondefs[rj];
            if(byte_ranges_overlap(region.offset, region.length, other.offset, other.length)) begin
                errors = append_validation_error(errors, "BlueCSR validation failed: regions " + region.identifier + " and " + other.identifier + " overlap.");
            end
        end
        for(Integer rj = 0; rj < length(regdefs); rj = rj + 1) begin
            let regdef = regdefs[rj];
            if(byte_ranges_overlap(region.offset, region.length, regdef.offset, valueOf(TDiv#(dw, 8)))) begin
                errors = append_validation_error(errors, "BlueCSR validation failed: region " + region.identifier + " overlaps register " + regdef.identifier + ".");
            end
        end
    end

    for(Integer fi = 0; fi < length(regfields); fi = fi + 1) begin
        let rf = regfields[fi];
        Integer regdef_count = count_regdefs_at(regdefs, rf.offset);
        if(regdef_count == 0) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: field " + rf.identifier + " at offset 0x" + integerToString(rf.offset) + " has no parent csr_reg_def.");
        end
        else if(regdef_count > 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: field " + rf.identifier + " at offset 0x" + integerToString(rf.offset) + " matches multiple csr_reg_def entries.");
        end

        if(rf.bit_offset < 0) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: field " + rf.identifier + " has negative bit offset.");
        end
        if(rf.width <= 0) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: field " + rf.identifier + " has non-positive width.");
        end
        if((rf.bit_offset + rf.width) > valueOf(dw)) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: field " + rf.identifier + " exceeds register width " + integerToString(valueOf(dw)) + ".");
        end

        for(Integer fj = fi + 1; fj < length(regfields); fj = fj + 1) begin
            let other = regfields[fj];
            if((rf.offset == other.offset) && field_ranges_overlap(rf, other)) begin
                errors = append_validation_error(errors, "BlueCSR validation failed: fields " + rf.identifier + " and " + other.identifier + " overlap in register offset 0x" + integerToString(rf.offset) + ".");
            end
        end
    end

    for(Integer i = 0; i < length(pure_reads); i = i + 1) begin
        if(count_regdefs_at(regdefs, pure_reads[i].offs) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: pure read at offset 0x" + integerToString(pure_reads[i].offs) + " does not resolve to exactly one csr_reg_def.");
        end
    end

    for(Integer i = 0; i < length(impure_reads); i = i + 1) begin
        if(count_regdefs_at(regdefs, impure_reads[i].offs) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: impure read at offset 0x" + integerToString(impure_reads[i].offs) + " does not resolve to exactly one csr_reg_def.");
        end
    end

    for(Integer i = 0; i < length(writes); i = i + 1) begin
        if(count_regdefs_at(regdefs, writes[i].offs) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: write op at offset 0x" + integerToString(writes[i].offs) + " does not resolve to exactly one csr_reg_def.");
        end
    end

    for(Integer i = 0; i < length(pure_read_regions); i = i + 1) begin
        if(count_regions_exact(regiondefs, pure_read_regions[i].offs, pure_read_regions[i].length) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: pure read region at offset 0x" + integerToString(pure_read_regions[i].offs) + " does not resolve to exactly one csr_region_def.");
        end
    end

    for(Integer i = 0; i < length(write_regions); i = i + 1) begin
        if(count_regions_exact(regiondefs, write_regions[i].offs, write_regions[i].length) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: write region at offset 0x" + integerToString(write_regions[i].offs) + " does not resolve to exactly one csr_region_def.");
        end
    end

    for(Integer i = 0; i < length(regiondefs); i = i + 1) begin
        let region = regiondefs[i];
        Bool has_read = False;
        Bool has_write = False;
        for(Integer j = 0; j < length(pure_read_regions); j = j + 1) begin
            has_read = has_read || ((pure_read_regions[j].offs == region.offset) && (pure_read_regions[j].length == region.length));
        end
        for(Integer j = 0; j < length(write_regions); j = j + 1) begin
            has_write = has_write || ((write_regions[j].offs == region.offset) && (write_regions[j].length == region.length));
        end
        if(!(has_read || has_write)) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: region " + region.identifier + " has no bound read or write handler.");
        end
    end

    for(Integer i = 0; i < length(access_policies); i = i + 1) begin
        let ap = access_policies[i];
        Integer target_count = count_regdefs_at(regdefs, ap.offset);
        if(ap.length != word_bytes) begin
            target_count = target_count + count_regions_exact(regiondefs, ap.offset, ap.length);
        end
        else begin
            target_count = target_count + count_regions_exact(regiondefs, ap.offset, ap.length);
        end
        if(count_access_policies_exact(access_policies, ap.offset, ap.length) != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: duplicate protection policy definitions at offset 0x" + integerToString(ap.offset) + ".");
        end
        if(target_count != 1) begin
            errors = append_validation_error(errors, "BlueCSR validation failed: protection policy at offset 0x" + integerToString(ap.offset) + " does not resolve to exactly one register or region.");
        end
    end

    return RegMapValidation_t {
        valid: errors == "",
        errors: errors,
        map_name: map_name,
        map_description: map_description
    };
endfunction

module [BlueCSRCtx_t#(dw)] csr_regmap_def#(String name, String desc)();
    RegMapEntry_t#(dw) entry = tagged RegMapDef RegMapDef_t {
        name:           name,
        description:    desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(dw)] csr_reg_def#(Integer offs, String ident, String desc)();
    RegMapEntry_t#(dw) entry = tagged RegDef RegDef_t {
        offset:         offs,
        identifier:     ident,
        description:    desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(dw)] csr_region_def#(Integer offs, Integer len, String ident, String desc)();
    RegMapEntry_t#(dw) entry = tagged RegRegionDef RegRegionDef_t {
        offset:         offs,
        length:         len,
        identifier:     ident,
        description:    desc
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(dw)] csr_reg_prot#(Integer offs, AccessPolicy_t read_policy, AccessPolicy_t write_policy)();
    RegMapEntry_t#(dw) entry = tagged AccessPolicyDef AccessPolicyDef_t {
        offset: offs,
        length: valueOf(TDiv#(dw, 8)), //access policies for a register affect all bytes associated with it
        read_policy: read_policy,
        write_policy: write_policy
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(dw)] csr_region_prot#(Integer offs, Integer len, AccessPolicy_t read_policy, AccessPolicy_t write_policy)();
    RegMapEntry_t#(dw) entry = tagged AccessPolicyDef AccessPolicyDef_t {
        offset: offs,
        length: len,
        read_policy: read_policy,
        write_policy: write_policy
    };
    addToCollection(entry);
endmodule

module [BlueCSRCtx_t#(dw)] csr_reg_rc#(Integer offs, t v, Integer bitpos, String ident, String name, String desc)() 
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw)
    );
    function Bit#(dw) do_read(Bit#(aw) _a);
        return field_read_pure(v, bitpos);
    endfunction

    String reset_value = "0x" + integerToHex(bit_to_integer(pack(v)));
    addToCollection(tagged ReadOpPure ReadOpPure_t { offs: offs, f_read: do_read });

    RegMapEntry_t#(dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset:         offs,
        identifier:     ident,
        name:           name,
        description:    desc,
        bit_offset:     bitpos,
        width:          valueOf(sz_t),
        reset_value:    reset_value
    };
    addToCollection(field_entry);
endmodule

module [BlueCSRCtx_t#(dw)] csr_reg_rw#(Integer offs, t rv, Integer bitpos, String ident, String fname, String desc)(Reg#(t)) 
    provisos(
        Bits#(t, sz_t),
        FieldReadPure#(t, dw),
        Add#(sz_t, a__, dw),
        Mul#(TDiv#(dw, 8), 8, dw),
        Div#(dw, 8, TDiv#(dw, 8))
    );

    Reg#(t) r <- mkReg(rv);

    String reset_value = "0x" + integerToHex(bit_to_integer(pack(rv)));

    function Bit#(dw) do_read(Bit#(aw) _a);
        return field_read_pure(r, bitpos);
    endfunction
    addToCollection(tagged ReadOpPure ReadOpPure_t { offs: offs, f_read: do_read } );

    function Action do_write(Bit#(aw) _a, Bit#(dw) d, Bit#(TDiv#(dw, 8)) s);
        action
            field_write_strobed(r, bitpos, d, s);
        endaction
    endfunction
    addToCollection(tagged WriteOp WriteOp_t { offs: offs, f_write: do_write });

    RegMapEntry_t#(dw) field_entry = tagged RegFieldDef RegFieldDef_t {
        offset:         offs,
        identifier:     ident,
        name:           fname,
        description:    desc,
        bit_offset:     bitpos,
        width:          valueOf(sz_t),
        reset_value:    reset_value
    };
    addToCollection(field_entry);

    return r;
endmodule

module [BlueCSRCtx_t#(dw)] csr_region_ro#(Integer offs, Integer len, String ident, String desc, function Bit#(dw) read_fn(Bit#(dw) local_addr))();
    function Bit#(dw) do_read(Bit#(dw) local_addr);
        return read_fn(local_addr);
    endfunction
    addToCollection(tagged ReadRegionPure ReadRegionPure_t {
        offs: offs,
        length: len,
        f_read: do_read
    });
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

module [BlueCSRCtx_t#(dw)] csr_region_wo#(Integer offs, Integer len, String ident, String desc, function Action write_fn(Bit#(dw) local_addr, Bit#(dw) data))();
    function Action do_write(Bit#(dw) local_addr, Bit#(dw) d);
        action
            write_fn(local_addr, d);
        endaction
    endfunction
    addToCollection(tagged WriteRegion WriteRegion_t {
        offs: offs,
        length: len,
        f_write: do_write
    });
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

module [BlueCSRCtx_t#(dw)] csr_region_rw#(Integer offs, Integer len, String ident, String desc, function Bit#(dw) read_fn(Bit#(dw) local_addr), function Action write_fn(Bit#(dw) local_addr, Bit#(dw) data))();
    function Bit#(dw) do_read(Bit#(dw) local_addr);
        return read_fn(local_addr);
    endfunction
    function Action do_write(Bit#(dw) local_addr, Bit#(dw) d);
        action
            write_fn(local_addr, d);
        endaction
    endfunction
    addToCollection(tagged ReadRegionPure ReadRegionPure_t {
        offs: offs,
        length: len,
        f_read: do_read
    });
    addToCollection(tagged WriteRegion WriteRegion_t {
        offs: offs,
        length: len,
        f_write: do_write
    });
    Empty _ <- csr_region_def(offs, len, ident, desc);
endmodule

function List#(RegFieldDef_t) find_fields_by_offs(List#(RegMapEntry_t) l, Integer offs);
    function Bool p(RegMapEntry_t entry);
        return case(entry) matches
            tagged RegFieldDef .regf: (regf.offset == offs);
            default: False;
        endcase
    endfunction
    return filter(p, l);
endfunction

function List#(ReadOpPure_t) find_pure_reads_by_offs(List#(RegMapEntry_t) l, Integer offs);
    function Bool p(RegMapEntry_t entry);
        return case(entry) matches
            tagged ReadOpPure_t .pure_read_op: (pure_read_op.offset == offs);
            default: False;
        endcase
    endfunction
    return filter(p, l);
endfunction

interface BusAccess_ifc#(type ext_ifc, type int_ifc);
    interface ext_ifc external;
    interface int_ifc internal;
endinterface

typedef BusAccess_ifc#(BlueCSR_ifc#(aw, dw), int_ifc) BlueCSRAccess_ifc#(numeric type aw, numeric type dw, type int_ifc);

module [Module] create_blue_csr#(BlueCSRCtx_t#(dw, i) ctx)(BlueCSRAccess_ifc#(aw, dw, i)) provisos(Add#(a__, dw, aw));

    let {coll_device_ifc, c} <- getCollection(ctx);

    //statically validate CSR definitions
    let validation = validate_blue_csr_entries(c);
    if(!validation.valid) begin
        errorM(validation.errors);
    end

    let regdefs             = List::concat(List::map(get_reg_def, c));
    let regiondefs          = List::concat(List::map(get_reg_region_def, c));
    let access_policies     = List::concat(List::map(get_access_policy_def, c));
    let pure_reads          = List::concat(List::map(get_pure_read, c));
    let pure_read_regions   = List::concat(List::map(get_pure_read_region, c));
    let write_regions       = List::concat(List::map(get_write_region, c));

    Integer word_bytes = valueOf(TDiv#(dw, 8));

    Reg#(Bool) rg_validation_failed <- mkReg(!validation.valid);

    function AccessPolicy_t lookup_read_policy(Integer offs, Integer len);
        AccessPolicy_t policy = CSR_ALLOW_ALL;
        for(Integer i = 0; i < length(access_policies); i = i + 1) begin
            if((access_policies[i].offset == offs) && (access_policies[i].length == len)) begin
                policy = access_policies[i].read_policy;
            end
        end
        return policy;
    endfunction

    function AccessPolicy_t lookup_write_policy(Integer offs, Integer len);
        AccessPolicy_t policy = CSR_ALLOW_ALL;
        for(Integer i = 0; i < length(access_policies); i = i + 1) begin
            if((access_policies[i].offset == offs) && (access_policies[i].length == len)) begin
                policy = access_policies[i].write_policy;
            end
        end
        return policy;
    endfunction

    function Bool is_word_aligned(Bit#(aw) addr);
        return (bit_to_integer(addr) % word_bytes) == 0;
    endfunction

    function Bool is_region_addr(Bit#(aw) addr, Integer offs, Integer len);
        return (addr >= fromInteger(offs)) && (addr < fromInteger(offs + len));
    endfunction

    //read rules for all defined registers, implemented at field granularity
    for(Integer i = 0; i < List::length(regdefs); i = i + 1) begin
        let fields = find_fields_by_offs(regdefs[i].offset);
    end

    function Bit#(dw) do_read_pure(Bit#(aw) addr);
        function Bit#(dw) fold_fn(Bit#(dw) acc, RegMapEntry_t#(dw) entry);
            case (entry) matches
                tagged ReadOpPure .op:
                    return acc | (fromInteger(op.offs) == addr ? op.f_read(addr) : 0);
                tagged ReadRegionPure .op:
                    return acc | ((addr >= fromInteger(op.offs)) && (addr < fromInteger(op.offs + op.length)) ? op.f_read(truncate(addr - fromInteger(op.offs))) : 0);
                default: return acc;
            endcase
        endfunction
        return List::foldl(fold_fn, 0, c);
    endfunction

    function BlueCSRReadRs_t#(dw) do_read(Bit#(aw) addr, BlueCSRProt_t prot);
        Bool reg_hit = False;
        Bool region_hit = False;
        Bool region_aligned = True;
        Bool allowed = True;
        BlueCSRReadRs_t#(dw) resp = bluecsr_read_resp(0, CSR_DECERR);

        for(Integer i = 0; i < length(regdefs); i = i + 1) begin
            if(fromInteger(regdefs[i].offset) == addr) begin
                reg_hit = True;
                allowed = access_policy_allows(lookup_read_policy(regdefs[i].offset, word_bytes), prot);
            end
        end

        for(Integer i = 0; i < length(regiondefs); i = i + 1) begin
            if(is_region_addr(addr, regiondefs[i].offset, regiondefs[i].length)) begin
                region_hit = True;
                region_aligned = is_word_aligned(addr);
                allowed = access_policy_allows(lookup_read_policy(regiondefs[i].offset, regiondefs[i].length), prot);
            end
        end

        if(reg_hit || region_hit) begin
            if(region_hit && !region_aligned) begin
                resp = bluecsr_read_resp(0, CSR_SLVERR);
            end
            else if(!allowed) begin
                resp = bluecsr_read_resp(0, CSR_SLVERR);
            end
            else begin
                resp = bluecsr_read_resp(do_read_pure(addr), CSR_OKAY);
            end
        end
        return resp;
    endfunction

    function Action dispatch_write_strobed(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe);
        function Action fold_write_fn(Action acc, RegMapEntry_t#(dw) entry);
            case (entry) matches
                tagged WriteOp .op:
                    return action
                        acc;
                        if(fromInteger(op.offs) == addr) begin
                            op.f_write(addr, data, strobe);
                        end
                    endaction;
                tagged WriteRegion .op:
                    return action
                        acc;
                        if((addr >= fromInteger(op.offs)) && (addr < fromInteger(op.offs + op.length))) begin
                            op.f_write(truncate(addr - fromInteger(op.offs)), data);
                        end
                    endaction;
                default:
                    return acc;
            endcase
        endfunction
        return List::foldl(fold_write_fn, noAction, c);
    endfunction

    function ActionValue#(BlueCSRWriteRs_t) do_write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe, BlueCSRProt_t prot);
        actionvalue
            Bool reg_hit = False;
            Bool region_hit = False;
            Bool region_aligned = True;
            Bool allowed = True;
            BlueCSRWriteRs_t resp = bluecsr_write_resp(CSR_DECERR);

            for(Integer i = 0; i < length(regdefs); i = i + 1) begin
                if(fromInteger(regdefs[i].offset) == addr) begin
                    reg_hit = True;
                    allowed = access_policy_allows(lookup_write_policy(regdefs[i].offset, word_bytes), prot);
                end
            end

            for(Integer i = 0; i < length(regiondefs); i = i + 1) begin
                if(is_region_addr(addr, regiondefs[i].offset, regiondefs[i].length)) begin
                    region_hit = True;
                    region_aligned = is_word_aligned(addr);
                    allowed = access_policy_allows(lookup_write_policy(regiondefs[i].offset, regiondefs[i].length), prot);
                end
            end

            if(reg_hit || region_hit) begin
                if(region_hit && !region_aligned) begin
                    resp = bluecsr_write_resp(CSR_SLVERR);
                end
                else if(region_hit && (strobe != '1)) begin
                    resp = bluecsr_write_resp(CSR_SLVERR);
                end
                else if(!allowed) begin
                    resp = bluecsr_write_resp(CSR_SLVERR);
                end
                else begin
                    dispatch_write_strobed(addr, data, strobe);
                    resp = bluecsr_write_resp(CSR_OKAY);
                end
            end
            return resp;
        endactionvalue
    endfunction

    rule fail_invalid_map (rg_validation_failed);
        $display("%s", validation.errors);
        $fatal(1);
    endrule

    interface BlueCSR_ifc external;

        method ActionValue#(BlueCSRWriteRs_t) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe, BlueCSRProt_t prot);
            actionvalue
                let resp <- do_write(addr, data, strobe, prot);
                return resp;
            endactionvalue
        endmethod
    
        method Action write_strobed(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe);
            action
                let _ <- do_write(addr, data, strobe, CSR_SECURE);
            endaction
        endmethod

        method BlueCSRReadRs_t#(dw) read(Bit#(aw) addr, BlueCSRProt_t prot);
            return do_read(addr, prot);
        endmethod

        method Bit#(dw) read_pure(Bit#(aw) addr);
            return do_read(addr, CSR_SECURE).data;
        endmethod

        method ActionValue#(Bit#(dw)) read_impure(Bit#(aw) addr);
            actionvalue
                return do_read(addr, CSR_SECURE).data;
            endactionvalue
        endmethod

    endinterface

    interface internal = coll_device_ifc;

endmodule



endpackage