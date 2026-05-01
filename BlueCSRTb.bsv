package BlueCSRTb;

import StmtFSM :: *;

import BlueCSR :: *;

function Action drive_idle(BlueCSR_ifc#(aw, dw) cfg);
    action
        cfg.valid(0);
        cfg.wr(0);
        cfg.addr(0);
        cfg.wdata(0);
        cfg.wstrb(0);
        cfg.prot(CSR_SECURE);
    endaction
endfunction

function Action issue_read(BlueCSR_ifc#(aw, dw) cfg, Bit#(aw) addr, BlueCSRProt_t prot);
    action
        cfg.valid(1);
        cfg.wr(0);
        cfg.addr(addr);
        cfg.wdata(0);
        cfg.wstrb(0);
        cfg.prot(prot);
    endaction
endfunction

function ActionValue#(Tuple2#(Bit#(dw), BlueCSRResponse_t)) accept_read_response(BlueCSR_ifc#(aw, dw) cfg);
    actionvalue
        return tuple2(cfg.rdata, cfg.resp);
    endactionvalue
endfunction

function Action issue_write(BlueCSR_ifc#(aw, dw) cfg, Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw, 8)) strobe, BlueCSRProt_t prot);
    action
        cfg.valid(1);
        cfg.wr(1);
        cfg.addr(addr);
        cfg.wdata(data);
        cfg.wstrb(strobe);
        cfg.prot(prot);
    endaction
endfunction

function ActionValue#(BlueCSRResponse_t) accept_write_response(BlueCSR_ifc#(aw, dw) cfg);
    actionvalue
        return cfg.resp;
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


endpackage