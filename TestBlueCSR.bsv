package TestBlueCSR;

import StmtFSM :: *;

import BlueLib :: *;
import BlueAXI :: *;
import BlueCSR :: *;
import BlueCSRExport :: *;
import Vector :: *;

typedef enum { Mode0, Mode1, Mode2 } Mode_t deriving(Bits, Eq, FShow);

interface ModConfig_ifc;
    method Bool en;
    method Mode_t mode;
endinterface


module [BlueCSRCtx_t#(32, 32)] module_config(ModConfig_ifc);

    Empty e = ?;
    Reg#(Bool)      rg_ctrl_en;
    Reg#(Mode_t)    rg_ctrl_mode;
    Vector#(4, Reg#(Bit#(32))) rg_table <- replicateM(mkReg(0));

    csr_regmap_def("testBlueCSR", "Test BlueCSR register map");

    csr_reg_def('h00, "MIV", "Module ID and Version Register");
    e <- csr_reg_rc('h00, Bit#(12)'('hABC),   0, "MID", "Module ID",       "Unique ID for this module.");
    e <- csr_reg_rc('h00, Bit#(12)'('hDDA),  16, "VRS", "Module Version",  "Module release version.");

    csr_reg_def('h04, "CTRL", "Module control register");
    rg_ctrl_en   <- csr_reg_rw('h04, False, 0, "CTRLEN",    "Control Enable",       "Controls whether module is enabled or not.");
    rg_ctrl_mode <- csr_reg_rw('h04, Mode1, 4, "MODE",      "Control Mode Setting", "Controls operating mode.");
    csr_reg_prot('h04, CSR_ALLOW_ALL, CSR_SEC_SECURE_ONLY);

    csr_reg_def('h08, "STS", "Module status register");

    function Bit#(32) table_read(Bit#(32) local_addr);
        Bit#(2) idx = truncate(local_addr >> 2);
        return rg_table[idx];
    endfunction

    function Action table_write(Bit#(32) local_addr, Bit#(32) data);
        action
            Bit#(2) idx = truncate(local_addr >> 2);
            rg_table[idx] <= data;
        endaction
    endfunction

    csr_region_rw('h100, 16, "TBL", "Table window", table_read, table_write);
    csr_region_prot('h100, 16, CSR_ALLOW_ALL, CSR_SEC_INSECURE_ONLY);

    method en   = rg_ctrl_en;
    method mode = rg_ctrl_mode;

endmodule

module mkTestBlueCSR(Empty);

    BlueCSRAccess_ifc#(32, 32, ModConfig_ifc) cfg <- create_blue_csr(module_config);
    BlueCSRExport_ifc rdl_export <- export_systemrdl_blue_csr(module_config, "sim/testBlueCSR.rdl");

    RegMapDoc_t#(32) doc <- doc_blue_csr(module_config);

    messageM(doc.reg_defs);

    function Action issue_read(Bit#(32) addr, BlueCSRProt_t prot);
        action
            cfg.external.read_request(True, BlueCSRReadReq_t {
                addr: addr,
                prot: prot
            });
        endaction
    endfunction

    function ActionValue#(BlueCSRReadRs_t#(32)) accept_read_response();
        actionvalue
            if(!cfg.external.read_response_valid) begin
                printColorTimed(RED, $format("Sanity fail: read response was not valid"));
                $finish();
            end
            let resp = cfg.external.read_response;
            cfg.external.read_response_ready(True);
            return resp;
        endactionvalue
    endfunction

    function Action issue_write(Bit#(32) addr, Bit#(32) data, Bit#(4) strobe, BlueCSRProt_t prot);
        action
            cfg.external.write_request(True, BlueCSRWriteReq_t {
                addr: addr,
                data: data,
                strobe: strobe,
                prot: prot
            });
        endaction
    endfunction

    function ActionValue#(BlueCSRWriteRs_t) accept_write_response();
        actionvalue
            if(!cfg.external.write_response_valid) begin
                printColorTimed(RED, $format("Sanity fail: write response was not valid"));
                $finish();
            end
            let resp = cfg.external.write_response;
            cfg.external.write_response_ready(True);
            return resp;
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
            $display("BUS[0x00]: %08x", bus0.data);
        endaction

        // issue_read(4, CSR_SECURE);
        // action
        //     let ctrl_reset_rsp <- accept_read_response();
        //     $display("BUS[0x04] reset: %08x", ctrl_reset_rsp.data);
        // endaction

        // issue_read(4, CSR_SECURE);
        // action
        //     let ctrl_reset_rsp <- accept_read_response();
        //     if(ctrl_reset_rsp.data != 'h00000010) begin
        //         printColorTimed(RED, $format("Sanity fail: reset CTRL expected 0x00000010 got %08x", ctrl_reset_rsp.data));
        //         $finish();
        //     end
        // endaction

        // issue_write('h04, 'h00000021, 'b1111, CSR_INSECURE);
        // action
        //     let denied_ctrl <- accept_write_response();
        //     if(denied_ctrl.resp != CSR_SLVERR) begin
        //         printColorTimed(RED, $format("Sanity fail: insecure CTRL write expected SLVERR"));
        //         $finish();
        //     end
        // endaction

        // issue_read(4, CSR_SECURE);
        // action
        //     let denied_ctrl_state <- accept_read_response();
        //     if(denied_ctrl_state.data != 'h00000010) begin
        //         printColorTimed(RED, $format("Sanity fail: denied CTRL write changed state"));
        //         $finish();
        //     end
        // endaction

        // //set CTRLEN=1 (bit 0) and MODE=Mode2 (bits 5:4 => b10)
        // issue_write('h04, 'h00000021, 'b1111, CSR_SECURE);
        // action
        //     let allowed_ctrl <- accept_write_response();
        //     if(allowed_ctrl.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: secure CTRL write expected OKAY"));
        //         $finish();
        //     end
        // endaction

        // issue_read('h04, CSR_INSECURE);
        // action
        //     let ctrl_after <- accept_read_response();
        //     if(ctrl_after.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: CTRL read expected OKAY"));
        //         $finish();
        //     end
        //     if(ctrl_after.data != 'h00000021) begin
        //         printColorTimed(RED, $format("Sanity fail: CTRL write expected 0x00000021 got %08x", ctrl_after.data));
        //         $finish();
        //     end
        //     if(cfg.internal.en != True) begin
        //         printColorTimed(RED, $format("Sanity fail: internal en expected True"));
        //         $finish();
        //     end
        //     if(cfg.internal.mode != Mode2) begin
        //         printColorTimed(RED, $format("Sanity fail: internal mode expected Mode2"));
        //         $finish();
        //     end
        // endaction

        // //strobe only byte 1; byte 0 fields must remain unchanged.
        // issue_write('h04, 'h0000AA00, 'b0010, CSR_SECURE);
        // action
        //     let strobed_ctrl <- accept_write_response();
        //     if(strobed_ctrl.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: strobed CTRL write expected OKAY"));
        //         $finish();
        //     end
        // endaction

        // issue_read(4, CSR_SECURE);
        // action
        //     let ctrl_strobe <- accept_read_response();
        //     if(ctrl_strobe.data != 'h00000021) begin
        //         printColorTimed(RED, $format("Sanity fail: strobed write changed CTRL unexpectedly: %08x", ctrl_strobe.data));
        //         $finish();
        //     end
        // endaction

        // issue_write('h100, 'hDEADBEEF, 'b1111, CSR_INSECURE);
        // action
        //     let denied_tbl <- accept_write_response();
        //     if(denied_tbl.resp != CSR_SLVERR) begin
        //         printColorTimed(RED, $format("Sanity fail: insecure table write expected SLVERR"));
        //         $finish();
        //     end
        // endaction

        // issue_write('h100, 'hDEADBEEF, 'b0011, CSR_SECURE);
        // action
        //     let partial_tbl <- accept_write_response();
        //     if(partial_tbl.resp != CSR_SLVERR) begin
        //         printColorTimed(RED, $format("Sanity fail: partial-strobe table write expected SLVERR"));
        //         $finish();
        //     end
        // endaction

        // issue_write('h100, 'hDEADBEEF, 'b1111, CSR_SECURE);
        // action
        //     let allowed_tbl0 <- accept_write_response();
        //     if(allowed_tbl0.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: secure table write expected OKAY"));
        //         $finish();
        //     end
        // endaction

        // issue_write('h10C, 'h12345678, 'b1111, CSR_SECURE);
        // action
        //     let allowed_tbl3 <- accept_write_response();
        //     if(allowed_tbl3.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: secure table write expected OKAY"));
        //         $finish();
        //     end
        // endaction

        // issue_read('h100, CSR_INSECURE);
        // action
        //     let table0 <- accept_read_response();
        //     if(table0.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: table read expected OKAY"));
        //         $finish();
        //     end
        //     if(table0.data != 'hDEADBEEF) begin
        //         printColorTimed(RED, $format("Sanity fail: TBL[0] expected deadbeef got %08x", table0.data));
        //         $finish();
        //     end
        // endaction

        // issue_read('h10C, CSR_INSECURE);
        // action
        //     let table3 <- accept_read_response();
        //     if(table3.resp != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: table read expected OKAY"));
        //         $finish();
        //     end
        //     if(table3.data != 'h12345678) begin
        //         printColorTimed(RED, $format("Sanity fail: TBL[3] expected 12345678 got %08x", table3.data));
        //         $finish();
        //     end
        //     printColorTimed(GREEN, $format("Sanity pass: CTRL and table-region protection/error behavior verified."));
        // endaction
    endseq;

    mkAutoFSM(s);

endmodule

endpackage