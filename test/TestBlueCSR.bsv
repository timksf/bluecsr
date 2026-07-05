package TestBlueCSR;

import StmtFSM :: *;
import RegFile :: *;
import Connectable :: *;

import BlueAXI :: *;

import BlueCSR :: *;

typedef enum { Mode0, Mode1, Mode2 } Mode_t deriving(Bits, Eq, FShow);

interface ModConfig_ifc;
    method Bool     en;
    method Mode_t   mode;
    method Bit#(4)  dma_en;
    method Bit#(8)  lock;

    method Bit#(1)  sts_rstrb;

    method Action running(Bool b);
    method Action rxerr(Bool b);
endinterface

module [BlueCSRCtx_t#(32, 32)] module_config(ModConfig_ifc);

    Empty e = ?;

    Reg#(Bool)      rg_ctrl_en;
    Reg#(Mode_t)    rg_ctrl_mode;
    Reg#(Bit#(4))   rg_ctrl_sub_en;
    Reg#(Bit#(8))   rg_ctrl_lock;

    Reg#(Bool)      rg_sts_rxerr;
    Reg#(Bool)      rg_sts_run;

    Reg#(Bit#(1))   rg_sts_rstrb;

    RegFile#(Bit#(8), Bit#(8)) table0 <- mkRegFileFull;

    csr_regmap_def("testBlueCSR", "Test BlueCSR register map");

    csr_reg_def('h00, "MIV", "Module ID and Version Register");
    csr_reg_rc('h00, Bit#(12)'('hABC),   0, "MID", "Module ID",       "Unique ID for this module.");
    csr_reg_rc('h00, Bit#(12)'('hDDA),  16, "VRS", "Module Version",  "Module release version.");

    csr_reg_def ('h04, "CTRL", "Module control register");
    rg_ctrl_en      <- csr_reg_rw('h04, False,  0, "CTRLEN",    "Control Enable",               "Controls whether module is enabled or not.");
    rg_ctrl_mode    <- csr_reg_rw('h04, Mode1,  4, "MODE",      "Control Mode Setting",         "Controls operating mode.");
    rg_ctrl_sub_en  <- csr_reg_ws('h04,     0, 16, "DMAEN",     "Control DMA Engine Enable",    "Controls whether DMA engine inside module is enabled.");
    rg_ctrl_lock    <- csr_reg_wc('h04,  'hFF, 24, "LOCK",      "Control Lock",                 "Controls all locks whatever those might be.");
    csr_reg_prot('h04, CSR_SEC_SECURE_ONLY, CSR_SEC_SECURE_ONLY);

    csr_reg_def('h08, "STS", "Module status register");
    rg_sts_run      <- csr_reg_ro ('h08, False, 0, "RUNN",  "Status Running",          "Indicates IP active status.");
    rg_sts_rxerr    <- csr_reg_w1c('h08, False, 4, "RXERR", "Status Receive Error",    "Indicates Reception Error.");

    rg_sts_rstrb    <- csr_reg_trigr('h08, False,  "STSRD", "Status Read Access Strobe", "Indicates a bus read access to this register.");

    csr_region_rw('h100, 256, table0.sub, table0.upd, "Table0", "Table 0");

    method en       = rg_ctrl_en;
    method mode     = rg_ctrl_mode;
    method dma_en   = rg_ctrl_sub_en;

    method sts_rstrb = rg_sts_rstrb;

    method running  = rg_sts_run._write;
    method rxerr    = rg_sts_rxerr._write;

endmodule

(* synthesize *)
module mk_config(BlueCSRAccess_ifc#(32, 32, ModConfig_ifc));
    BlueCSRAccess_ifc#(32, 32, ModConfig_ifc) cfg <- create_blue_csr(module_config, False);
    BlueCSRExport_ifc rdl_export <- export_systemrdl_blue_csr(module_config, "sim/testBlueCSR.rdl");

    RegMapDoc_t#(32) doc <- doc_blue_csr(module_config);

    messageM(doc.reg_defs);
    return cfg;
endmodule

module [Module] mkTestBlueCSR(Empty);

    let cfg <- mk_config;
    let tb_lookup <- build_blue_csr_tb_lookup(module_config);

    Reg#(Bit#(32)) rg_addr <- mkReg(0);
    Reg#(Bit#(32)) rg_data <- mkReg(0);


    Stmt s = seq

        read_csr_reg_range(cfg.external, rg_addr, rg_data, tb_lookup, "MIV", "STS");

        issue_write_region(cfg.external, tb_lookup, "Table0", 'hAABBCCDD, 4'b1111, CSR_SECURE);
        expect_write_okay(cfg.external);
        
        read_csr_region_range(cfg.external, rg_addr, rg_data, tb_lookup, "Table0", 28);

        par
            issue_read_reg(cfg.external, tb_lookup, "STS", CSR_INSECURE);
            action
                if(cfg.internal.sts_rstrb != 1'b1) begin
                    $display("Status register read strobe not asserted");
                    $finish;
                end
            endaction
        endpar
        expect_read_okay(cfg.external);

        delay(5);
        $display("Finished TB");

    endseq;

    mkAutoFSM(s);

endmodule

endpackage