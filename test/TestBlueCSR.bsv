package TestBlueCSR;

import StmtFSM :: *;
import RegFile :: *;
import Connectable :: *;
import FIFOF :: *;

import BlueAXI :: *;

import BlueCSR :: *;

typedef enum { Mode0, Mode1, Mode2 } Mode_t deriving(Bits, Eq, FShow);

interface ModConfig_ifc;
    method Bool     en;
    method Mode_t   mode;
    method Bit#(4)  dma_en;
    method Bit#(8)  lock;
    method Bit#(4)  sticky_set;

    method Bit#(1)  sts_rstrb;
    method Bit#(1)  sts_rstrb2;

    method Action running(Bool b);
    method Action rxerr(Bool b);
    method Action sts_event(Bool b);
    method Action irq_rx_event(Bool b);
    method Action irq_tx_event(Bool b);
    method Action irq_fault_event(Bool b);
    method Action hu_update(Bit#(32) value);
    method Action fifo_error_enq(Bit#(8) value);
    method Action fifo_valid_enq(Bit#(8) value);
    method Bool fifo_write_not_empty;
    method Bit#(8) fifo_write_first;
    method Action fifo_write_deq;
endinterface

module [BlueCSRCtx_t#(32, 32)] module_config(ModConfig_ifc);

    Reg#(Bool)      rg_ctrl_en;
    Reg#(Mode_t)    rg_ctrl_mode;
    Reg#(Bit#(4))   rg_ctrl_sub_en;
    Reg#(Bit#(8))   rg_ctrl_lock;
    Reg#(Bit#(4))   rg_ctrl_sticky_set;

    Reg#(Bool)      rg_sts_run;

    Reg#(Bit#(1))   rg_sts_rstrb;
    Reg#(Bit#(1))   rg_sts_rstrb2;
    Wire#(Maybe#(Bool)) w_sts_rxerr_evt <- mkDWire(tagged Invalid);
    Wire#(Maybe#(Bool)) w_sts_evt       <- mkDWire(tagged Invalid);
    Wire#(Bool)     w_irq_rx_evt    <- mkDWire(False);
    Wire#(Bool)     w_irq_tx_evt    <- mkDWire(False);
    Wire#(Bool)     w_irq_fault_evt <- mkDWire(False);
    Wire#(Maybe#(Bit#(32))) w_hu_update <- mkDWire(tagged Invalid);

    RegFile#(Bit#(8), Bit#(8)) table0 <- mkRegFileFull;
    FIFOF#(Bit#(8)) fifo_error_read <- mkSizedFIFOF(1);
    FIFOF#(Bit#(8)) fifo_valid_read <- mkSizedFIFOF(1);
    FIFOF#(Bit#(8)) fifo_write <- mkSizedFIFOF(1);

    csr_regmap_def("testBlueCSR", "Test BlueCSR register map");

    csr_reg_def('h00, "MIV", "Module ID and Version Register");
    csr_reg_rc('h00, Bit#(12)'('hABC),   0, "MID", "Module ID",       "Unique ID for this module.");
    csr_reg_rc('h00, Bit#(12)'('hDDA),  16, "VRS", "Module Version",  "Module release version.");

    csr_reg_def ('h04, "CTRL", "Module control register");
    rg_ctrl_en          <- csr_reg_rw ('h04,   False,   0, "CTRLEN",    "Control Enable",               "Controls whether module is enabled or not.");
    rg_ctrl_mode        <- csr_reg_rw ('h04,   Mode1,   4, "MODE",      "Control Mode Setting",         "Controls operating mode.");
    rg_ctrl_sticky_set  <- csr_reg_w1s('h04, 4'b0010,   8, "STICKYSET", "Sticky Set",                   "Software can set but not clear these bits.");
    rg_ctrl_sub_en      <- csr_reg_ws ('h04,       0,  16, "DMAEN",     "Control DMA Engine Enable",    "Controls whether DMA engine inside module is enabled.");
    rg_ctrl_lock        <- csr_reg_wc ('h04,    'hFF,  24, "LOCK",      "Control Lock",                 "Controls all locks whatever those might be.");

    csr_reg_prot('h04, CSR_SEC_SECURE_ONLY, CSR_SEC_SECURE_ONLY);

    csr_reg_def('h08, "STS", "Module status register");
    rg_sts_run      <- csr_reg_ro ('h08, False,                  0, "RUNN",  "Status Running",          "Indicates IP active status.");
    let _rxerr      <- csr_reg_w1c('h08, False, 4, w_sts_rxerr_evt, "RXERR", "Status Receive Error", "Indicates Reception Error.");
    let _stsev      <- csr_reg_w1c('h08, False, 8, w_sts_evt,       "EVENT", "Event Status",          "Indicates a sticky hardware event.");
    rg_sts_rstrb    <- csr_reg_trigr('h08, False,                   "STSRD", "Status Rd Access Strobe", "Indicates a bus read access to this register.");
    rg_sts_rstrb2   <- csr_reg_trigr('h08, False,                   "STSR2", "Status Rd Access Strobe", "Checks multiple triggers at one offset.");

    csr_reg_def('h0C, "FIFO_RD", "Exclusive FIFO read register");
    csr_reg_fifo_ro('h0C, fifo_error_read, "DATA", "FIFO Data", "Returns SLVERR when the FIFO is empty.");

    csr_reg_def('h10, "FIFO_RD_VALID", "Non-failing FIFO read register");
    csr_reg_fifo_ro_valid(
        'h10,
        fifo_valid_read,
        "DATA",
        "FIFO Data",
        "FIFO data when VALID is set.",
        "VALID",
        "FIFO Data Valid",
        "Indicates that DATA was dequeued from the FIFO."
    );
    csr_reg_rc('h10, Bit#(8)'('hA5), 16, "CONST", "Constant Value", "Unrelated value field.");

    csr_reg_def('h14, "FIFO_WR", "Exclusive FIFO write register");
    csr_reg_fifo_wo('h14, fifo_write, "DATA", "FIFO Data", "Returns SLVERR when the FIFO is full.");

    csr_reg_def('h18, "IRQ_PENDING", "Interrupt pending register");
    csr_reg_def('h1C, "IRQ_ENABLE", "Interrupt enable register");
    csr_irq('h18, 'h1C, 0, 0, w_irq_rx_evt,     "RX_IRQ",       "Receive Interrupt",    "A receive event is pending.");
    csr_irq('h18, 'h1C, 1, 0, w_irq_tx_evt,     "TX_IRQ",       "Transmit Interrupt",   "A transmit event is pending.");
    csr_irq('h18, 'h1C, 2, 1, w_irq_fault_evt,  "FAULT_IRQ",    "Fault Interrupt",      "A fault event is pending.");

    csr_reg_def('h20, "HU", "Hardware-updatable register");
    ReadOnly#(Bit#(32)) rg_hu <- csr_reg_hu(
        'h20,
        'h12345678,
        0,
        w_hu_update,
        "VALUE",
        "Value",
        "Software-writable value with a hardware update input."
    );

    csr_region_rw('h100, 256, table0.sub, table0.upd, "Table0", "Table 0");

    method en           = rg_ctrl_en;
    method mode         = rg_ctrl_mode;
    method dma_en       = rg_ctrl_sub_en;
    method lock         = rg_ctrl_lock;
    method sticky_set   = rg_ctrl_sticky_set;

    method sts_rstrb    = rg_sts_rstrb;
    method sts_rstrb2   = rg_sts_rstrb2;

    method running              = rg_sts_run._write;
    method Action rxerr(Bool b);
        action
            if (b) begin
                w_sts_rxerr_evt <= tagged Valid True;
            end
        endaction
    endmethod
    method Action sts_event(Bool b);
        action
            if (b) begin
                w_sts_evt <= tagged Valid True;
            end
        endaction
    endmethod
    method irq_rx_event         = w_irq_rx_evt._write;
    method irq_tx_event         = w_irq_tx_evt._write;
    method irq_fault_event      = w_irq_fault_evt._write;
    method Action hu_update(Bit#(32) value);
        action
            w_hu_update <= tagged Valid value;
        endaction
    endmethod
    method fifo_error_enq       = fifo_error_read.enq;
    method fifo_valid_enq       = fifo_valid_read.enq;
    method fifo_write_not_empty = fifo_write.notEmpty;
    method fifo_write_first     = fifo_write.first;
    method fifo_write_deq       = fifo_write.deq;

endmodule

(* synthesize *)
module mk_config(BlueCSRAccess_ifc#(32, 32, 2, ModConfig_ifc));
    BlueCSRAccess_ifc#(32, 32, 2, ModConfig_ifc) cfg <- create_blue_csr(module_config, False);
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

    function Action expect_event(Bool expected);
        action
            let rsp <- accept_read_response(cfg.external);
            if(tpl_2(rsp) != CSR_OKAY || unpack(tpl_1(rsp)[8]) != expected) begin
                $display(
                    "W1C event mismatch: expected %0d, got %0d (%0d)",
                    expected,
                    tpl_1(rsp)[8],
                    tpl_2(rsp)
                );
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_read(Bit#(32) expected_data, BlueCSRResponse_t expected_resp);
        action
            let rsp <- accept_read_response(cfg.external);
            if(tpl_2(rsp) != expected_resp || tpl_1(rsp) != expected_data) begin
                $display(
                    "Read mismatch: expected data %08x response %0d, got %08x response %0d",
                    expected_data,
                    expected_resp,
                    tpl_1(rsp),
                    tpl_2(rsp)
                );
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_write(BlueCSRResponse_t expected_resp);
        action
            let rsp <- accept_write_response(cfg.external);
            if(rsp != expected_resp) begin
                $display("Write response mismatch: expected %0d, got %0d", expected_resp, rsp);
                $finish(1);
            end
        endaction
    endfunction

    Stmt s = seq

        read_csr_reg_range(cfg.external, rg_addr, rg_data, tb_lookup, "MIV", "STS");

        issue_write_region(cfg.external, tb_lookup, "Table0", 'hAABBCCDD, 4'b1111, CSR_SECURE);
        expect_write_okay(cfg.external);
        
        read_csr_region_range(cfg.external, rg_addr, rg_data, tb_lookup, "Table0", 28);

        issue_write(cfg.external, 'h04, 'h00000100, 4'b0010, CSR_SECURE);
        expect_write_okay(cfg.external);
        action
            if(cfg.internal.sticky_set != 4'b0011) begin
                $display("W1S field did not preserve already-set bits");
                $finish(1);
            end
        endaction

        issue_read(cfg.external, 'h20, CSR_INSECURE);
        expect_read('h12345678, CSR_OKAY);

        issue_write(cfg.external, 'h20, 'h11223344, 4'b1111, CSR_INSECURE);
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h20, CSR_INSECURE);
        expect_read('h11223344, CSR_OKAY);

        cfg.internal.hu_update('hAABBCCDD);
        delay(1);
        issue_read(cfg.external, 'h20, CSR_INSECURE);
        expect_read('hAABBCCDD, CSR_OKAY);

        action
            issue_write(cfg.external, 'h20, 'hDEADBEEF, 4'b1111, CSR_INSECURE);
            cfg.internal.hu_update('hFEEDFACE);
        endaction
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h20, CSR_INSECURE);
        expect_read('hFEEDFACE, CSR_OKAY);

        cfg.internal.rxerr(True);
        delay(1);
        issue_write(cfg.external, 'h08, 0, 4'b0001, CSR_INSECURE);
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h08, CSR_INSECURE);
        expect_read('h10, CSR_OKAY);
        issue_write(cfg.external, 'h08, 'h10, 4'b0001, CSR_INSECURE);
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h08, CSR_INSECURE);
        expect_read(0, CSR_OKAY);

        par
            issue_read_reg(cfg.external, tb_lookup, "STS", CSR_INSECURE);
            action
                if(cfg.internal.sts_rstrb != 1'b1 || cfg.internal.sts_rstrb2 != 1'b1) begin
                    $display("Status register read strobes not asserted");
                    $finish;
                end
            endaction
        endpar
        expect_read_okay(cfg.external);

        cfg.internal.sts_event(True);
        delay(1);

        issue_read(cfg.external, 'h08, CSR_INSECURE);
        expect_event(True);

        issue_write(cfg.external, 'h08, 'h100, 4'b0000, CSR_INSECURE);
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h08, CSR_INSECURE);
        expect_event(True);

        issue_write(cfg.external, 'h08, 'h100, 4'b0010, CSR_INSECURE);
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h08, CSR_INSECURE);
        expect_event(False);

        par
            issue_write(cfg.external, 'h08, 'h100, 4'b0010, CSR_INSECURE);
            cfg.internal.sts_event(True);
        endpar
        expect_write_okay(cfg.external);
        issue_read(cfg.external, 'h08, CSR_INSECURE);
        expect_event(True);

        issue_read(cfg.external, 'h0C, CSR_INSECURE);
        expect_read(0, CSR_SLVERR);

        issue_write(cfg.external, 'h0C, 0, 4'b1111, CSR_INSECURE);
        expect_write(CSR_DECERR);

        issue_read(cfg.external, 'h14, CSR_INSECURE);
        expect_read(0, CSR_DECERR);

        cfg.internal.fifo_error_enq('h5A);
        issue_read(cfg.external, 'h0C, CSR_INSECURE);
        expect_read('h5A, CSR_OKAY);

        issue_read(cfg.external, 'h10, CSR_INSECURE);
        expect_read('h00A50000, CSR_OKAY);

        cfg.internal.fifo_valid_enq('h3C);
        issue_read(cfg.external, 'h10, CSR_INSECURE);
        expect_read('h00A5013C, CSR_OKAY);

        issue_write(cfg.external, 'h14, 'h55, 4'b0011, CSR_INSECURE);
        expect_write(CSR_SLVERR);
        action
            if(cfg.internal.fifo_write_not_empty) begin
                $display("Partial FIFO write unexpectedly enqueued data");
                $finish(1);
            end
        endaction

        issue_write(cfg.external, 'h14, 'h66, 4'b0001, CSR_INSECURE);
        expect_write(CSR_OKAY);
        action
            if(!cfg.internal.fifo_write_not_empty || cfg.internal.fifo_write_first != 'h66) begin
                $display("FIFO write did not enqueue expected data");
                $finish(1);
            end
        endaction

        issue_write(cfg.external, 'h14, 'h77, 4'b0001, CSR_INSECURE);
        expect_write(CSR_SLVERR);
        cfg.internal.fifo_write_deq;

        cfg.internal.irq_rx_event(True);
        delay(1);
        action
            if(cfg.external.irqs[0] || cfg.external.irqs[1]) begin
                $display("Masked interrupt unexpectedly asserted an IRQ line");
                $finish(1);
            end
        endaction
        issue_read(cfg.external, 'h18, CSR_INSECURE);
        expect_read(1, CSR_OKAY);

        issue_write(cfg.external, 'h1C, 7, 4'b0001, CSR_INSECURE);
        expect_write(CSR_OKAY);
        par
            cfg.internal.irq_tx_event(True);
            cfg.internal.irq_fault_event(True);
        endpar
        delay(1);
        action
            if(!cfg.external.irqs[0] || !cfg.external.irqs[1]) begin
                $display("Enabled pending interrupts did not assert both IRQ lines");
                $finish(1);
            end
        endaction

        issue_write(cfg.external, 'h18, 1, 4'b0001, CSR_INSECURE);
        expect_write(CSR_OKAY);
        delay(1);
        action
            if(!cfg.external.irqs[0] || !cfg.external.irqs[1]) begin
                $display("Clearing RX incorrectly removed TX from the shared IRQ line");
                $finish(1);
            end
        endaction

        issue_write(cfg.external, 'h18, 2, 4'b0001, CSR_INSECURE);
        expect_write(CSR_OKAY);
        delay(1);
        action
            if(cfg.external.irqs[0] || !cfg.external.irqs[1]) begin
                $display("Shared IRQ line did not deassert after its last pending source cleared");
                $finish(1);
            end
        endaction

        issue_write(cfg.external, 'h18, 4, 4'b0001, CSR_INSECURE);
        expect_write(CSR_OKAY);
        delay(1);
        action
            if(cfg.external.irqs[0] || cfg.external.irqs[1]) begin
                $display("IRQ vector did not clear after all pending fields cleared");
                $finish(1);
            end
        endaction

        delay(5);
        $display("Finished TB");
        $finish(0);

    endseq;

    mkAutoFSM(s);

endmodule

endpackage
