package TestAPBAdapter;

import StmtFSM :: *;

import BlueFabric :: *;
import BlueCSR :: *;
import TestBlueCSR :: *;

module [Module] mkTestAPBAdapter(Empty);
    let cfg <- mk_config;
    BlueCSR_APB_ifc#(32, 32, 0, 2) apb_cfg <-
        mkBlueCSRAPBAdapter(cfg.external, True);

    Reg#(Bit#(32)) rg_address <- mkReg(0);
    Reg#(Bool)     rg_select  <- mkReg(False);
    Reg#(Bool)     rg_enable  <- mkReg(False);
    Reg#(Bool)     rg_write   <- mkReg(False);
    Reg#(Bit#(32)) rg_data    <- mkReg(0);
    Reg#(Bit#(4))  rg_strobe  <- mkReg(0);

    Reg#(Bit#(32)) rg_read_data   <- mkReg(0);
    Reg#(Bool)     rg_slave_error <- mkReg(False);

    rule r_drive_apb;
        apb_cfg.s_apb.ppaddr(rg_address);
        apb_cfg.s_apb.ppsel(rg_select);
        apb_cfg.s_apb.ppenable(rg_enable);
        apb_cfg.s_apb.ppwrite(rg_write);
        apb_cfg.s_apb.ppwdata(rg_data);
        apb_cfg.s_apb.ppstrb(rg_strobe);
        apb_cfg.s_apb.ppprot(0);
        apb_cfg.s_apb.ppauser(0);
        apb_cfg.s_apb.ppwuser(0);
    endrule

    function Stmt apb_transfer(
            Bool write,
            Bit#(32) address,
            Bit#(32) data,
            Bit#(4) strobe
        );
        return seq
            action
                rg_address <= address;
                rg_select  <= True;
                rg_enable  <= False;
                rg_write   <= write;
                rg_data    <= data;
                rg_strobe  <= strobe;
            endaction
            action
                rg_enable <= True;
            endaction
            while(!apb_cfg.s_apb.pready) noAction;
            action
                rg_read_data   <= apb_cfg.s_apb.prdata;
                rg_slave_error <= apb_cfg.s_apb.pslverr;
                rg_select      <= False;
                rg_enable      <= False;
            endaction
        endseq;
    endfunction

    Stmt test = seq
        apb_transfer(False, 'h00, 0, 0);
        action
            if(rg_read_data != 'h0DDA0ABC || rg_slave_error) begin
                $display(
                    "APB adapter read mismatch: %08x/%0d",
                    rg_read_data,
                    rg_slave_error
                );
                $finish(1);
            end
        endaction

        apb_transfer(True, 'h04, 1, 4'hF);
        action
            if(rg_slave_error) begin
                $display("APB adapter write unexpectedly failed");
                $finish(1);
            end
        endaction

        apb_transfer(False, 'h0C, 0, 0);
        action
            if(!rg_slave_error) begin
                $display("APB adapter did not propagate CSR_SLVERR");
                $finish(1);
            end
        endaction

        apb_transfer(False, 'h80, 0, 0);
        action
            if(rg_read_data != 0 || !rg_slave_error) begin
                $display(
                    "APB adapter did not translate CSR_DECERR: %08x/%0d",
                    rg_read_data,
                    rg_slave_error
                );
                $finish(1);
            end
        endaction

        cfg.internal.irq_rx_event(True);
        apb_transfer(True, 'h1C, 1, 4'hF);
        action
            if(rg_slave_error || !apb_cfg.irqs[0]) begin
                $display("APB adapter did not expose the upstream IRQ vector");
                $finish(1);
            end
        endaction

        apb_transfer(True, 'h18, 1, 4'hF);
        action
            if(rg_slave_error || apb_cfg.irqs[0]) begin
                $display("APB adapter IRQ vector did not follow pending W1C");
                $finish(1);
            end
        endaction

        $display("Finished APB adapter TB");
        $finish(0);
    endseq;

    mkAutoFSM(test);
endmodule

endpackage
