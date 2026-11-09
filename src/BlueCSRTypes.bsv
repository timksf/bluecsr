package BlueCSRTypes;

import List :: *;
import Vector :: *;
import GetPut :: *;
import ModuleCollect :: *;
import ClientServer :: *;

typedef enum {
    CSR_OKAY   = 2'b00,
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
    CSR_SECURE   = 1'b0,
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
    Bool               wr;
    Bit#(aw)           addr;
    Bit#(dw)           wdata;
    Bit#(TDiv#(dw, 8)) wstrb;
    BlueCSRProt_t      prot;
} BlueCSR_Req_t#(numeric type aw, numeric type dw) deriving(Eq, Bits, FShow);

typedef struct {
    Bit#(dw)          rdata;
    BlueCSRResponse_t resp;
} BlueCSR_Rsp_t#(numeric type dw) deriving(Eq, Bits, FShow);

typedef struct {
    Bit#(dw)           data;
    Bit#(TDiv#(dw, 8)) strobe;
} CSRRegWrite_t#(numeric type dw) deriving(Bits);

(*always_enabled*)
interface BlueCSR_Fab_ifc#(numeric type aw, numeric type dw);
    (*prefix = ""*) method Action valid ((*port = "i_valid"*) Bit#(1)            valid);
    (*prefix = ""*) method Action wr    ((*port = "i_wr"*)    Bit#(1)            wr   );
    (*prefix = ""*) method Action addr  ((*port = "i_addr"*)  Bit#(aw)           addr );
    (*prefix = ""*) method Action wdata ((*port = "i_data"*)  Bit#(dw)           data );
    (*prefix = ""*) method Action wstrb ((*port = "i_strb"*)  Bit#(TDiv#(dw, 8)) strb );
    (*prefix = ""*) method Action prot  ((*port = "i_prot"*)  BlueCSRProt_t      prot );

    (*result = "o_rdy"*)  method Bit#(1)           ready;
    (*result = "o_data"*) method Bit#(dw)          rdata;
    (*result = "o_resp"*) method BlueCSRResponse_t resp;
endinterface

interface BlueCSR_ifc#(numeric type aw, numeric type dw, numeric type ni);
    //no pure server to allow easy expansion of this interface
    interface Put#(BlueCSR_Req_t#(aw, dw)) request;
    interface Get#(BlueCSR_Rsp_t#(dw))     response;
    (* always_ready *)
    method Vector#(ni, Bool) irqs;
endinterface

typedef ModuleCollect#(RegMapEntry_t#(aw, dw), ifc) BlueCSRCtx_t#(numeric type aw, numeric type dw, type ifc);

typedef struct {
    String name;
    String description;
} RegMapDef_t;

typedef struct {
    Integer offset;
    Integer length;
    String  prefix;
    String  name;
    String  description;
} RegBlockDef_t;

typedef struct {
    Integer offset;
    String  identifier;
    String  description;
} RegDef_t;

typedef struct {
    Integer offset;
    Integer length;
    String  identifier;
    String  description;
} RegRegionDef_t;

typedef struct {
    Integer               offset;
    Integer               length;
    BlueCSRAccessPolicy_t read_policy;
    BlueCSRAccessPolicy_t write_policy;
} AccessPolicyDef_t;

typedef struct {
    Integer         offset;
    String          identifier;
    String          name;
    String          description;
    BlueCSRAccess_t access_type;
    Integer         bit_offset;
    Integer         width;
    String          reset_value;
} RegFieldDef_t;

typedef struct {
    Integer               offset;
    //combinational value contribution. Multiple entries at one offset are OR-composed to form the register word.
    function Bit#(dw) _() f_read;
} ReadOpPure_t#(numeric type dw);

typedef struct {
    Integer                                       offset;
    //effectful reads are separate because ActionValue methods participate in BSV scheduling (for example, FIFO reads dequeue an element)
    Bool                                          exclusive;
    function Bool _()                             can_read;
    BlueCSR_Rsp_t#(dw)                            unavailable_rsp;
    function ActionValue#(BlueCSR_Rsp_t#(dw)) _() f_read;
} ReadOpAction_t#(numeric type dw);

typedef struct {
    Integer                                             offset;
    function Action _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) f_write;
} WriteOp_t#(numeric type dw);

typedef struct {
    Integer                                                                      offset;
    Bool                                                                         exclusive;
    function Bool _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s)                            can_write;
    BlueCSRResponse_t                                                            unavailable_resp;
    function ActionValue#(BlueCSRResponse_t) _(Bit#(dw) d, Bit#(TDiv#(dw, 8)) s) f_write;
} WriteOpAction_t#(numeric type dw);

typedef struct {
    Integer                         offset;
    Integer                         length;
    function Bit#(dw) _(Bit#(aw) a) f_read;
} ReadRegion_t#(numeric type aw, numeric type dw);

typedef struct {
    Integer                                   offset;
    Integer                                   length;
    function Action _(Bit#(aw) a, Bit#(dw) d) f_write;
} WriteRegion_t#(numeric type aw, numeric type dw);

//request/response region: one response per request, in order, from a server with any latency
typedef struct {
    Integer                                             offset;
    Integer                                             length;
    Bool                                                can_access;
    BlueCSRResponse_t                                   unavailable_resp;
    Server#(BlueCSR_Req_t#(aw, dw), BlueCSR_Rsp_t#(dw)) server;
} ServerRegion_t#(numeric type aw, numeric type dw);

typedef struct {
    Integer             offset;
    Bool                delay;
    function Action _() trigger;
} ReadTrigger_t;

typedef struct {
    Integer             offset;
    Bool                delay;
    function Action _() trigger;
} WriteTrigger_t;

typedef struct {
    Integer line;
    Bool    active;
} IRQSource_t;

typedef union tagged {
    RegMapDef_t             RegMapDef;
    RegBlockDef_t           RegBlockDef;
    //scope marker distinguishes nested blocks from overlapping siblings
    void                    RegBlockEnd;
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
    ServerRegion_t#(aw, dw) ServerRegion;
    ReadTrigger_t           ReadTrigger;
    WriteTrigger_t          WriteTrigger;
    IRQSource_t             IRQSource;
} RegMapEntry_t#(numeric type aw, numeric type dw);

function List#(ReadOpPure_t#(dw))       get_pure_read        (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged ReadOpPure      .rr  ? Cons(rr, Nil)  : Nil;
function List#(ReadOpAction_t#(dw))     get_action_read      (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged ReadOpAction    .rr  ? Cons(rr, Nil)  : Nil;
function List#(WriteOp_t#(dw))          get_write_op         (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged WriteOp         .rr  ? Cons(rr, Nil)  : Nil;
function List#(WriteOpAction_t#(dw))    get_action_write     (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged WriteOpAction   .rr  ? Cons(rr, Nil)  : Nil;
function List#(ReadRegion_t#(aw, dw))   get_read_region      (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged ReadRegion      .rr  ? Cons(rr, Nil)  : Nil;
function List#(WriteRegion_t#(aw, dw))  get_write_region     (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged WriteRegion     .rr  ? Cons(rr, Nil)  : Nil;
function List#(ServerRegion_t#(aw, dw)) get_server_region    (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged ServerRegion    .rr  ? Cons(rr, Nil)  : Nil;
function List#(AccessPolicyDef_t)       get_access_policy_def(RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged AccessPolicyDef .rr  ? Cons(rr, Nil)  : Nil;
function List#(RegFieldDef_t)           get_regfield_def     (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged RegFieldDef     .rr  ? Cons(rr, Nil)  : Nil;
function List#(RegDef_t)                get_reg_def          (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged RegDef          .rr  ? Cons(rr, Nil)  : Nil;
function List#(RegRegionDef_t)          get_reg_region_def   (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged RegRegionDef    .rr  ? Cons(rr, Nil)  : Nil;
function List#(RegBlockDef_t)           get_reg_block_def    (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged RegBlockDef     .rr  ? Cons(rr, Nil)  : Nil;
function List#(RegMapDef_t)             get_regmap_def       (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged RegMapDef       .rr  ? Cons(rr, Nil)  : Nil;
function List#(ReadTrigger_t)           get_read_trigger     (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged ReadTrigger     .rr  ? Cons(rr, Nil)  : Nil;
function List#(WriteTrigger_t)          get_write_trigger    (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged WriteTrigger    .rr  ? Cons(rr, Nil)  : Nil;
function List#(IRQSource_t)             get_irq_source       (RegMapEntry_t#(aw, dw) regmap_entry) = regmap_entry matches tagged IRQSource       .irq ? Cons(irq, Nil) : Nil;

typedef struct {
    String reg_defs;
} RegMapDoc_t#(numeric type dw);

typedef struct {
    Bool   valid;
    String errors;
    String map_name;
    String map_description;
} RegMapValidation_t;

interface BlueCSRExport_ifc;
    method Bool done;
    method Bool success;
endinterface

function String append_newline(String acc, String msg);
    if(acc == "") return msg;
    else return acc + "\n" + msg;
endfunction

function Integer count_regdefs_at(List#(RegDef_t) regdefs, Integer offs);
    Integer count = 0;
    for (Integer i = 0; i < length(regdefs); i = i + 1) begin
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

function Bool is_power_of_two(Integer value);
    Bool    result    = value > 0;
    Integer remaining = value;
    while (remaining > 1) begin
        result    = result && ((remaining % 2) == 0);
        remaining = remaining / 2;
    end
    return result;
endfunction

function Integer count_regions_exact(List#(RegRegionDef_t) regions, Integer offs, Integer len);
    Integer count = 0;
    for (Integer i = 0; i < length(regions); i = i + 1) begin
        if((regions[i].offset == offs) && (regions[i].length == len)) begin
            count = count + 1;
        end
    end
    return count;
endfunction

function Integer count_access_policies_exact(List#(AccessPolicyDef_t) policies, Integer offs, Integer len);
    Integer count = 0;
    for (Integer i = 0; i < length(policies); i = i + 1) begin
        if((policies[i].offset == offs) && (policies[i].length == len)) begin
            count = count + 1;
        end
    end
    return count;
endfunction

endpackage
