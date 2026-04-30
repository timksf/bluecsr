package TestBlueCSR;

import StmtFSM :: *;

import BlueCSR :: *;
import BlueCSRTb :: *;
import BlueCSRExport :: *;

typedef enum { Mode0, Mode1, Mode2 } Mode_t deriving(Bits, Eq, FShow);

interface ModConfig_ifc;
    method Bool en;
    method Mode_t mode;
endinterface

typedef enum {
    BLUE,
    RED,
    YELLOW,
    GREEN,
    NORMAL
} DisplayColors deriving(Bits, Eq, FShow);

function Action printColor(DisplayColors color, Fmt text);
    action
        Fmt colorFmt = ?;
        case(color)
            BLUE: colorFmt = $format("%c[34m",27);
            RED: colorFmt = $format("%c[31m",27);
            YELLOW: colorFmt = $format("%c[33m",27);
            GREEN: colorFmt = $format("%c[32m",27);
            NORMAL: colorFmt = $format("");
        endcase
        $display(colorFmt + text + $format("%c[0m",27));
    endaction
endfunction

function Action printColorTimed(DisplayColors color, Fmt text);
    action
        let s <- $time;
        printColor(color, $format("(%0d) ", s) + text);
    endaction
endfunction

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
    e <- csr_reg_prot('h04, CSR_SEC_SECURE_ONLY, CSR_SEC_SECURE_ONLY);

    e <- csr_reg_def('h08, "STS", "Module status register");

    method en   = rg_ctrl_en;
    method mode = rg_ctrl_mode;

endmodule

(* synthesize *)
module mk_config(BlueCSRAccess_ifc#(32, 32, ModConfig_ifc));
    BlueCSRAccess_ifc#(32, 32, ModConfig_ifc) cfg <- create_blue_csr(module_config);
    BlueCSRExport_ifc rdl_export <- export_systemrdl_blue_csr(module_config, "sim/testBlueCSR.rdl");

    RegMapDoc_t#(32) doc <- doc_blue_csr(module_config);

    messageM(doc.reg_defs);
    return cfg;
endmodule

module [Module] mkTestBlueCSR(Empty);

    let cfg <- mk_config;

    Reg#(Bit#(32)) rg_addr <- mkReg(0);
    Reg#(Bit#(32)) rg_data <- mkReg(0);

    Stmt s = seq
        printColorTimed(BLUE, $format("Hello World!"));

        read_csr_range(cfg.external, rg_addr, rg_data, 0, 8);

        // issue_read(0, CSR_SECURE);
        // action
        //     let bus0 <- accept_read_response();
        //     $display("BUS[0x00]: %08x", tpl_1(bus0));
        // endaction
        // drive_idle();

        // issue_read(cfg.external, 'h04, CSR_SECURE);
        // action
        //     let ctrl_reset_rsp <- accept_read_response(cfg.external);
        //     if(tpl_2(ctrl_reset_rsp) != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: reset CTRL read expected OKAY"));
        //         $finish();
        //     end
        //     if(tpl_1(ctrl_reset_rsp) != 'h00000010) begin
        //         printColorTimed(RED, $format("Sanity fail: reset CTRL expected 0x00000010 got %08x", tpl_1(ctrl_reset_rsp)));
        //         $finish();
        //     end
        // endaction
        drive_idle(cfg.external);

        // issue_write('h04, 'h00000021, 'b1111, CSR_INSECURE);
        // action
        //     let denied_ctrl <- accept_write_response();
        //     if(denied_ctrl != CSR_SLVERR) begin
        //         printColorTimed(RED, $format("Sanity fail: insecure CTRL write expected SLVERR"));
        //         $finish();
        //     end
        // endaction
        // drive_idle();

        // issue_write('h04, 'h00000021, 'b1111, CSR_SECURE);
        // action
        //     let allowed_ctrl <- accept_write_response();
        //     if(allowed_ctrl != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: secure CTRL write expected OKAY"));
        //         $finish();
        //     end
        // endaction
        // drive_idle();

        // issue_read('h04, CSR_INSECURE);
        // action
        //     let ctrl_after <- accept_read_response();
        //     if(tpl_2(ctrl_after) != CSR_OKAY) begin
        //         printColorTimed(RED, $format("Sanity fail: CTRL read expected OKAY"));
        //         $finish();
        //     end
        //     if(tpl_1(ctrl_after) != 'h00000021) begin
        //         printColorTimed(RED, $format("Sanity fail: CTRL write expected 0x00000021 got %08x", tpl_1(ctrl_after)));
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
        // drive_idle();
    endseq;

    mkAutoFSM(s);

endmodule

endpackage