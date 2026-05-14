package BlueCSRTb;

import List :: *;
import GetPut :: *;
import ModuleCollect :: *;
import StmtFSM :: *;

import BlueCSRCtx :: *;

typedef struct {
    List#(RegDef_t) regdefs;
    List#(RegRegionDef_t) regiondefs;
} BlueCSRTbLookup_t#(numeric type aw, numeric type dw);

module [Module] build_blue_csr_tb_lookup#(BlueCSRCtx_t#(aw, dw, i) ctx)(BlueCSRTbLookup_t#(aw, dw));
    let {_, c} <- getCollection(ctx);
    let regdefs = List::concat(List::map(get_reg_def, c));
    let regiondefs = List::concat(List::map(get_reg_region_def, c));

    return BlueCSRTbLookup_t {
        regdefs: regdefs,
        regiondefs: regiondefs
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

function Maybe#(Integer) lookup_blue_csr_reg_offset(BlueCSRTbLookup_t#(aw, dw) lookup, String ident);
    let regdefs = find_regdefs_by_identifier(lookup.regdefs, ident);
    return List::length(regdefs) == 0 ? tagged Invalid : tagged Valid List::head(regdefs).offset;
endfunction

function Maybe#(Integer) lookup_blue_csr_region_offset(BlueCSRTbLookup_t#(aw, dw) lookup, String ident);
    let regiondefs = find_regiondefs_by_identifier(lookup.regiondefs, ident);
    return List::length(regiondefs) == 0 ? tagged Invalid : tagged Valid List::head(regiondefs).offset;
endfunction

function Stmt fail_blue_csr_lookup(String kind, String ident);
    Stmt s = seq
        action
            $display("BlueCSRTb %s lookup failed for identifier %s", kind, ident);
            $finish();
        endaction
    endseq;
    return s;
endfunction

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