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


module [BlueCSRCtx_t#(32)] module_config(ModConfig_ifc);

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

        $display("BUS[0x00]: %08x", cfg.external.read_pure(0));
        $display("BUS[0x04] reset: %08x", cfg.external.read_pure(4));

        action
            Bit#(32) ctrl_reset = cfg.external.read_pure(4);
            if(ctrl_reset != 'h00000010) begin
                printColorTimed(RED, $format("Sanity fail: reset CTRL expected 0x00000010 got %08x", ctrl_reset));
                $finish();
            end
        endaction

        action
            let denied_ctrl <- cfg.external.write('h04, 'h00000021, 'b1111, CSR_INSECURE);
            if(denied_ctrl.resp != CSR_SLVERR) begin
                printColorTimed(RED, $format("Sanity fail: insecure CTRL write expected SLVERR"));
                $finish();
            end
            if(cfg.external.read_pure(4) != 'h00000010) begin
                printColorTimed(RED, $format("Sanity fail: denied CTRL write changed state"));
                $finish();
            end
        endaction

        //set CTRLEN=1 (bit 0) and MODE=Mode2 (bits 5:4 => b10)
        action
            let allowed_ctrl <- cfg.external.write('h04, 'h00000021, 'b1111, CSR_SECURE);
            if(allowed_ctrl.resp != CSR_OKAY) begin
                printColorTimed(RED, $format("Sanity fail: secure CTRL write expected OKAY"));
                $finish();
            end
        endaction

        action
            let ctrl_after = cfg.external.read('h04, CSR_INSECURE);
            if(ctrl_after.resp != CSR_OKAY) begin
                printColorTimed(RED, $format("Sanity fail: CTRL read expected OKAY"));
                $finish();
            end
            if(ctrl_after.data != 'h00000021) begin
                printColorTimed(RED, $format("Sanity fail: CTRL write expected 0x00000021 got %08x", ctrl_after.data));
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

        //strobe only byte 1; byte 0 fields must remain unchanged.
        cfg.external.write_strobed('h04, 'h0000AA00, 'b0010);

        action
            Bit#(32) ctrl_strobe = cfg.external.read_pure(4);
            if(ctrl_strobe != 'h00000021) begin
                printColorTimed(RED, $format("Sanity fail: strobed write changed CTRL unexpectedly: %08x", ctrl_strobe));
                $finish();
            end
        endaction

        action
            let denied_tbl <- cfg.external.write('h100, 'hDEADBEEF, 'b1111, CSR_INSECURE);
            if(denied_tbl.resp != CSR_SLVERR) begin
                printColorTimed(RED, $format("Sanity fail: insecure table write expected SLVERR"));
                $finish();
            end
            let partial_tbl <- cfg.external.write('h100, 'hDEADBEEF, 'b0011, CSR_SECURE);
            if(partial_tbl.resp != CSR_SLVERR) begin
                printColorTimed(RED, $format("Sanity fail: partial-strobe table write expected SLVERR"));
                $finish();
            end
            let allowed_tbl0 <- cfg.external.write('h100, 'hDEADBEEF, 'b1111, CSR_SECURE);
            let allowed_tbl3 <- cfg.external.write('h10C, 'h12345678, 'b1111, CSR_SECURE);
            if((allowed_tbl0.resp != CSR_OKAY) || (allowed_tbl3.resp != CSR_OKAY)) begin
                printColorTimed(RED, $format("Sanity fail: secure table write expected OKAY"));
                $finish();
            end
        endaction

        action
            let table0 = cfg.external.read('h100, CSR_INSECURE);
            let table3 = cfg.external.read('h10C, CSR_INSECURE);
            if((table0.resp != CSR_OKAY) || (table3.resp != CSR_OKAY)) begin
                printColorTimed(RED, $format("Sanity fail: table read expected OKAY"));
                $finish();
            end
            if(table0.data != 'hDEADBEEF) begin
                printColorTimed(RED, $format("Sanity fail: TBL[0] expected deadbeef got %08x", table0.data));
                $finish();
            end
            if(table3.data != 'h12345678) begin
                printColorTimed(RED, $format("Sanity fail: TBL[3] expected 12345678 got %08x", table3.data));
                $finish();
            end
            printColorTimed(GREEN, $format("Sanity pass: CTRL and table-region protection/error behavior verified."));
        endaction
    endseq;

    mkAutoFSM(s);

endmodule

endpackage