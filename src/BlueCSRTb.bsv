package BlueCSRTb;

import List :: *;
import GetPut :: *;
import ModuleCollect :: *;
import StmtFSM :: *;

import BlueAXI :: *;

import BlueCSRCore :: *;

interface BlueCSRTbAccessor_ifc#(numeric type dw);
    method ActionValue#(Integer)                                  reg_offset(String reg_ident);
    method ActionValue#(Integer)                                  field_bit(String reg_ident, String field_ident);

    method Action                                                 read_reg_req(String reg_ident);
    method ActionValue#(Tuple2#(Bit#(dw), BlueCSRResponse_t))     read_reg_rsp();
    method Action                                                 write_reg_req(String reg_ident, Bit#(dw) data);
    method Action                                                 write_reg_req_strb(String reg_ident, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb);
    method ActionValue#(BlueCSRResponse_t)                        write_reg_rsp();
endinterface

typedef struct {
    List#(RegDef_t) regdefs;
    List#(RegRegionDef_t) regiondefs;
    List#(RegFieldDef_t) regfields;
} BlueCSRTbLookup_t#(numeric type aw, numeric type dw);

module [Module] build_blue_csr_tb_lookup#(BlueCSRCtx_t#(aw, dw, i) ctx)(BlueCSRTbLookup_t#(aw, dw));
    let {_, c} <- getCollection(ctx);
    let regdefs = List::concat(List::map(get_reg_def, c));
    let regiondefs = List::concat(List::map(get_reg_region_def, c));
    let regfields = List::concat(List::map(get_regfield_def, c));

    return BlueCSRTbLookup_t {
        regdefs: regdefs,
        regiondefs: regiondefs,
        regfields: regfields
    };
endmodule

function List#(RegDef_t) find_regdefs_by_identifier(List#(RegDef_t) regdefs, String ident);
    function Bool p(RegDef_t regdef) = regdef.identifier == ident;
    return List::filter(p, regdefs);
endfunction

function List#(RegRegionDef_t) find_regiondefs_by_identifier(List#(RegRegionDef_t) regiondefs, String ident);
    function Bool p(RegRegionDef_t regiondef) = regiondef.identifier == ident;
    return List::filter(p, regiondefs);
endfunction

function List#(RegFieldDef_t) find_regfields_by_reg_offset(List#(RegFieldDef_t) regfields, Integer reg_offs, String ident);
    function Bool p(RegFieldDef_t regfield) = regfield.offset == reg_offs && regfield.identifier == ident;
    return List::filter(p, regfields);
endfunction

function Maybe#(Integer) lookup_blue_csr_reg_offset(BlueCSRTbLookup_t#(aw, dw) lookup, String ident);
    let regdefs = find_regdefs_by_identifier(lookup.regdefs, ident);
    return List::length(regdefs) == 0 ? tagged Invalid : tagged Valid List::head(regdefs).offset;
endfunction

function Maybe#(Integer) lookup_blue_csr_region_offset(BlueCSRTbLookup_t#(aw, dw) lookup, String ident);
    let regiondefs = find_regiondefs_by_identifier(lookup.regiondefs, ident);
    return List::length(regiondefs) == 0 ? tagged Invalid : tagged Valid List::head(regiondefs).offset;
endfunction

function Maybe#(RegFieldDef_t) lookup_blue_csr_field_at_offset(BlueCSRTbLookup_t#(aw, dw) lookup, Integer reg_offs, String field_ident);
    let regfields = find_regfields_by_reg_offset(lookup.regfields, reg_offs, field_ident);
    return List::length(regfields) == 0 ? tagged Invalid : tagged Valid List::head(regfields);
endfunction

function Maybe#(RegFieldDef_t) lookup_blue_csr_field(BlueCSRTbLookup_t#(aw, dw) lookup, String reg_ident, String field_ident);
    if (lookup_blue_csr_reg_offset(lookup, reg_ident) matches tagged Valid .reg_offs) begin
        return lookup_blue_csr_field_at_offset(lookup, reg_offs, field_ident);
    end
    else begin
        return tagged Invalid;
    end
endfunction

function Stmt fail_blue_csr_lookup(String kind, String ident);
    Stmt s = seq
        action
            $display("[ERROR] BlueCSRTb %s lookup failed for identifier %s", kind, ident);
            $finish();
        endaction
    endseq;
    return s;
endfunction

function ActionValue#(Integer) expect_blue_csr_reg_offset(BlueCSRTbLookup_t#(aw, dw) lookup, String ident);
    actionvalue
        Integer rg_offs = ?;
        if (lookup_blue_csr_reg_offset(lookup, ident) matches tagged Valid .offs) begin
            rg_offs = offs;
        end
        else begin
            $display("[ERROR] BlueCSRTb register lookup failed for identifier %s", ident);
            $finish();
        end
        return rg_offs;
    endactionvalue
endfunction

function ActionValue#(Integer) expect_blue_csr_field_bit(BlueCSRTbLookup_t#(aw, dw) lookup, String reg_ident, String field_ident);
    actionvalue
        let reg_offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
        Integer rg_bitpos = ?;
        if (lookup_blue_csr_field_at_offset(lookup, reg_offs, field_ident) matches tagged Valid .field) begin
            rg_bitpos = field.bit_offset;
        end
        else begin
            $display("[ERROR] BlueCSRTb field lookup failed for identifier %s.%s", reg_ident, field_ident);
            $finish();
        end
        return rg_bitpos;
    endactionvalue
endfunction

function BlueCSRResponse_t axi4_lite_to_bluecsr_resp(AXI4_Lite_Response resp);
    return case (resp)
        OKAY:   CSR_OKAY;
        EXOKAY: CSR_EXOKAY;
        SLVERR: CSR_SLVERR;
        DECERR: CSR_DECERR;
    endcase;
endfunction

module [Module] mkBlueCSRTbAccessorAXI4Lite#(
    BlueCSRTbLookup_t#(aw, dw) lookup,
    AXI4_Lite_Master_Rd#(aw, dw) rd,
    AXI4_Lite_Master_Wr#(aw, dw) wr
)(BlueCSRTbAccessor_ifc#(dw));
    method ActionValue#(Integer) reg_offset(String reg_ident);
        let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
        return offs;
    endmethod

    method ActionValue#(Integer) field_bit(String reg_ident, String field_ident);
        let bitpos <- expect_blue_csr_field_bit(lookup, reg_ident, field_ident);
        return bitpos;
    endmethod

    method Action read_reg_req(String reg_ident);
        action
            let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
            rd.request.put(AXI4_Lite_Read_Rq_Pkg {
                addr: fromInteger(offs),
                prot: UNPRIV_SECURE_DATA
            });
        endaction
    endmethod

    method ActionValue#(Tuple2#(Bit#(dw), BlueCSRResponse_t)) read_reg_rsp();
        actionvalue
            let rsp <- rd.response.get();
            return tuple2(rsp.data, axi4_lite_to_bluecsr_resp(rsp.resp));
        endactionvalue
    endmethod

    method Action write_reg_req(String reg_ident, Bit#(dw) data);
        action
            let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
            wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: fromInteger(offs),
                prot: UNPRIV_SECURE_DATA,
                data: data,
                strb: unpack(-1)
            });
        endaction
    endmethod

    method Action write_reg_req_strb(String reg_ident, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb);
        action
            let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
            wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: fromInteger(offs),
                prot: UNPRIV_SECURE_DATA,
                data: data,
                strb: strb
            });
        endaction
    endmethod

    method ActionValue#(BlueCSRResponse_t) write_reg_rsp();
        actionvalue
            let rsp <- wr.response.get();
            return axi4_lite_to_bluecsr_resp(rsp.resp);
        endactionvalue
    endmethod
endmodule

module [Module] mkBlueCSRTbAccessorBlueCSR#(
    BlueCSRTbLookup_t#(aw, dw) lookup,
    BlueCSR_ifc#(aw, dw) csr
)(BlueCSRTbAccessor_ifc#(dw));
    method ActionValue#(Integer) reg_offset(String reg_ident);
        let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
        return offs;
    endmethod

    method ActionValue#(Integer) field_bit(String reg_ident, String field_ident);
        let bitpos <- expect_blue_csr_field_bit(lookup, reg_ident, field_ident);
        return bitpos;
    endmethod

    method Action read_reg_req(String reg_ident);
        action
            let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
            csr.request.put(
                BlueCSR_Req_t {
                    wr:     False,
                    addr:   fromInteger(offs),
                    wdata:  ?,
                    wstrb:  ?,
                    prot:   CSR_INSECURE
                }
            );
        endaction
    endmethod

    method ActionValue#(Tuple2#(Bit#(dw), BlueCSRResponse_t)) read_reg_rsp();
        let rsp <- accept_read_response(csr);
        return rsp;
    endmethod

    method Action write_reg_req(String reg_ident, Bit#(dw) data);
        action
            let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
            csr.request.put(
                BlueCSR_Req_t {
                    wr:     True,
                    addr:   fromInteger(offs),
                    wdata:  data,
                    wstrb:  unpack(-1),
                    prot:   CSR_INSECURE
                }
            );
        endaction
    endmethod

    method Action write_reg_req_strb(String reg_ident, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strb);
        action
            let offs <- expect_blue_csr_reg_offset(lookup, reg_ident);
            csr.request.put(
                BlueCSR_Req_t {
                    wr:     True,
                    addr:   fromInteger(offs),
                    wdata:  data,
                    wstrb:  strb,
                    prot:   CSR_INSECURE
                }
            );
        endaction
    endmethod

    method ActionValue#(BlueCSRResponse_t) write_reg_rsp();
        let rsp <- accept_write_response(csr);
        return rsp;
    endmethod
endmodule

function Action issue_read(BlueCSR_ifc#(aw, dw) cfg, Bit#(aw) addr, BlueCSRProt_t prot);
    action
        cfg.request.put(
            BlueCSR_Req_t {
                wr:     False,
                addr:   addr,
                wdata:  ?,
                wstrb:  ?,
                prot:   prot
            }
        );
    endaction
endfunction

function ActionValue#(Tuple2#(Bit#(dw), BlueCSRResponse_t)) accept_read_response(BlueCSR_ifc#(aw, dw) cfg);
    actionvalue
        let r <- cfg.response.get;
        return tuple2(r.rdata, r.resp);
    endactionvalue
endfunction

function Action issue_write(BlueCSR_ifc#(aw, dw) cfg, Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe, BlueCSRProt_t prot);
    action
        cfg.request.put(
            BlueCSR_Req_t {
                wr:     True,
                addr:   addr,
                wdata:  data,
                wstrb:  strobe,
                prot:   prot
            }
        );
    endaction
endfunction

function ActionValue#(BlueCSRResponse_t) accept_write_response(BlueCSR_ifc#(aw, dw) cfg);
    actionvalue
        let r <- cfg.response.get;
        return r.resp;
    endactionvalue
endfunction

function Stmt expect_write_okay(BlueCSR_ifc#(aw, dw) cfg);
    Stmt s = seq
        action
            let bus_resp <- accept_write_response(cfg);
            if(bus_resp != CSR_OKAY) begin
                $write("Expected OKAY response to write but got "); $display(fshow(bus_resp));
                $finish();
            end
        endaction
    endseq;
    return s;
endfunction

function Stmt expect_read_okay(BlueCSR_ifc#(aw, dw) cfg);
    Stmt s = seq
        action
            let bus_resp <- accept_read_response(cfg);
            if(tpl_2(bus_resp) != CSR_OKAY) begin
                $write("Expected OKAY response to write but got "); $display(fshow(tpl_2(bus_resp)));
                $finish();
            end
        endaction
    endseq;
    return s;
endfunction

function Stmt issue_read_reg(BlueCSR_ifc#(aw, dw) cfg, BlueCSRTbLookup_t#(aw, dw) lookup, String ident, BlueCSRProt_t prot);
    Stmt s = fail_blue_csr_lookup("register", ident);
    if (lookup_blue_csr_reg_offset(lookup, ident) matches tagged Valid .offs) begin
        s = seq
            issue_read(cfg, fromInteger(offs), prot);
        endseq;
    end
    return s;
endfunction

function Stmt issue_write_region(BlueCSR_ifc#(aw, dw) cfg, BlueCSRTbLookup_t#(aw, dw) lookup, String ident, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe, BlueCSRProt_t prot);
    Stmt s = fail_blue_csr_lookup("region", ident);
    if (lookup_blue_csr_region_offset(lookup, ident) matches tagged Valid .offs) begin
        s = seq
            issue_write(cfg, fromInteger(offs), data, strobe, prot);
        endseq;
    end
    return s;
endfunction

function Stmt read_csr_range(BlueCSR_ifc#(aw, dw) cfg, Reg#(Bit#(aw)) rg_addr, Reg#(Bit#(dw)) rg_data, Integer lo_addr, Integer hi_addr);
    Stmt s = seq
        rg_addr <= fromInteger(lo_addr);
        while(rg_addr < fromInteger(hi_addr)) seq
            issue_read(cfg, rg_addr, CSR_INSECURE);
            action
                let bus0 <- accept_read_response(cfg);
                $write("BUS[0x%02x]: <", rg_addr); $write(fshow(tpl_2(bus0)));
                $display(">\t %08x", tpl_1(bus0));
            endaction
            rg_addr <= rg_addr + 4;
        endseq
    endseq;
    return s;
endfunction

function Stmt read_csr_reg_range(BlueCSR_ifc#(aw, dw) cfg, Reg#(Bit#(aw)) rg_addr, Reg#(Bit#(dw)) rg_data, BlueCSRTbLookup_t#(aw, dw) lookup, String lo_ident, String hi_ident);
    Stmt s = fail_blue_csr_lookup("register", lo_ident);
    if (lookup_blue_csr_reg_offset(lookup, lo_ident) matches tagged Valid .lo_offs) begin
        s = fail_blue_csr_lookup("register", hi_ident);
        if (lookup_blue_csr_reg_offset(lookup, hi_ident) matches tagged Valid .hi_offs) begin
            s = read_csr_range(cfg, rg_addr, rg_data, lo_offs, hi_offs);
        end
    end
    return s;
endfunction

function Stmt read_csr_region_range(BlueCSR_ifc#(aw, dw) cfg, Reg#(Bit#(aw)) rg_addr, Reg#(Bit#(dw)) rg_data, BlueCSRTbLookup_t#(aw, dw) lookup, String ident, Integer byte_count);
    Stmt s = fail_blue_csr_lookup("region", ident);
    if (lookup_blue_csr_region_offset(lookup, ident) matches tagged Valid .offs) begin
        s = read_csr_range(cfg, rg_addr, rg_data, offs, offs + byte_count);
    end
    return s;
endfunction


endpackage