package TestBlueCSR;

import StmtFSM :: *;

import BlueLib :: *;
import BlueCSR :: *;
import BlueCSRExport :: *;

typedef enum { Mode0, Mode1, Mode2 } Mode_t deriving(Bits, Eq, FShow);

interface ModConfig_ifc;
    method Bool en;
    method Mode_t mode;
endinterface


module [BlueCSRCtx_t#(32, 32)] module_config(ModConfig_ifc);

    Empty e = ?;
    Reg#(Bool)      rg_ctrl_en;
    Reg#(Mode_t)    rg_ctrl_mode;

    e <- csr_regmap_def("testBlueCSR", "Test BlueCSR register map");

    e <- csr_reg_def('h00, "MIV", "Module ID and Version Register");
    e <- csr_reg_rc('h00, Bit#(12)'('hABC),   0, "MID", "Module ID",       "Unique ID for this module.");
    e <- csr_reg_rc('h00, Bit#(12)'('hDDA),  16, "VRS", "Module Version",  "Module release version.");

    e <- csr_reg_def('h04, "CTRL", "Module control register");
    rg_ctrl_en   <- csr_reg_rw('h04, False, 0, "CTRLEN",    "Control Enable",       "Controls whether module is enabled or not.");
    rg_ctrl_mode <- csr_reg_rw('h04, Mode1, 4, "MODE",      "Control Mode Setting", "Controls operating mode.");
    e <- csr_reg_prot('h04, CSR_ALLOW_ALL, CSR_SEC_SECURE_ONLY);

    e <- csr_reg_def('h08, "STS", "Module status register");

    method en   = rg_ctrl_en;
    method mode = rg_ctrl_mode;

endmodule

module [Module] mkTestBlueCSR(Empty);

    BlueCSRAccess_ifc#(32, 32, ModConfig_ifc) cfg <- create_blue_csr(module_config);
    BlueCSRExport_ifc rdl_export <- export_systemrdl_blue_csr(module_config, "sim/testBlueCSR.rdl");

    RegMapDoc_t#(32) doc <- doc_blue_csr(module_config);

    messageM(doc.reg_defs);

    function Action drive_idle();
        action
            cfg.external.valid(0);
            cfg.external.wr(0);
            cfg.external.addr(0);
            cfg.external.wdata(0);
            cfg.external.wstrb(0);
            cfg.external.prot(CSR_SECURE);
        endaction
    endfunction

    function Action issue_read(Bit#(32) addr, BlueCSRProt_t prot);
        action
            cfg.external.valid(1);
            cfg.external.wr(0);
            cfg.external.addr(addr);
            cfg.external.wdata(0);
            cfg.external.wstrb(0);
            cfg.external.prot(prot);
        endaction
    endfunction

    function ActionValue#(Tuple2#(Bit#(32), BlueCSRResponse_t)) accept_read_response();
        actionvalue
            return tuple2(cfg.external.rdata, cfg.external.resp);
        endactionvalue
    endfunction

    function Action issue_write(Bit#(32) addr, Bit#(32) data, Bit#(4) strobe, BlueCSRProt_t prot);
        action
            cfg.external.valid(1);
            cfg.external.wr(1);
            cfg.external.addr(addr);
            cfg.external.wdata(data);
            cfg.external.wstrb(strobe);
            cfg.external.prot(prot);
        endaction
    endfunction

    function ActionValue#(BlueCSRResponse_t) accept_write_response();
        actionvalue
            return cfg.external.resp;
        endactionvalue
    endfunction

    Stmt s = seq
        printColorTimed(BLUE, $format("Hello World!"));

        while(!rdl_export.done) noAction;

        action
            if(!rdl_export.success) begin
                printColorTimed(RED, $format("SystemRDL export failed."));
                $finish();
            end
            printColorTimed(GREEN, $format("SystemRDL export completed."));
        endaction

        issue_read(0, CSR_SECURE);
        action
            let bus0 <- accept_read_response();
            $display("BUS[0x00]: %08x", tpl_1(bus0));
        endaction
        drive_idle();

        issue_read('h04, CSR_SECURE);
        action
            let ctrl_reset_rsp <- accept_read_response();
            if(tpl_2(ctrl_reset_rsp) != CSR_OKAY) begin
                printColorTimed(RED, $format("Sanity fail: reset CTRL read expected OKAY"));
                $finish();
            end
            if(tpl_1(ctrl_reset_rsp) != 'h00000010) begin
                printColorTimed(RED, $format("Sanity fail: reset CTRL expected 0x00000010 got %08x", tpl_1(ctrl_reset_rsp)));
                $finish();
            end
        endaction
        drive_idle();

        issue_write('h04, 'h00000021, 'b1111, CSR_INSECURE);
        action
            let denied_ctrl <- accept_write_response();
            if(denied_ctrl != CSR_SLVERR) begin
                printColorTimed(RED, $format("Sanity fail: insecure CTRL write expected SLVERR"));
                $finish();
            end
        endaction
        drive_idle();

        issue_write('h04, 'h00000021, 'b1111, CSR_SECURE);
        action
            let allowed_ctrl <- accept_write_response();
            if(allowed_ctrl != CSR_OKAY) begin
                printColorTimed(RED, $format("Sanity fail: secure CTRL write expected OKAY"));
                $finish();
            end
        endaction
        drive_idle();

        issue_read('h04, CSR_INSECURE);
        action
            let ctrl_after <- accept_read_response();
            if(tpl_2(ctrl_after) != CSR_OKAY) begin
                printColorTimed(RED, $format("Sanity fail: CTRL read expected OKAY"));
                $finish();
            end
            if(tpl_1(ctrl_after) != 'h00000021) begin
                printColorTimed(RED, $format("Sanity fail: CTRL write expected 0x00000021 got %08x", tpl_1(ctrl_after)));
                $finish();
            end
            if(cfg.internal.en != True) begin
                printColorTimed(RED, $format("Sanity fail: internal en expected True"));
                $finish();
            end
            if(cfg.internal.mode != Mode2) begin
                printColorTimed(RED, $format("Sanity fail: internal mode expected Mode2"));
                $finish();
            end
        endaction
        drive_idle();
    endseq;

    mkAutoFSM(s);

endmodule

endpackage