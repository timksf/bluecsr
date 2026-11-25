package ExampleSoC;

import DefaultValue :: *;
import GetPut       :: *;
import Vector       :: *;

import Ahb                :: *;
import AhbAddrMap         :: *;
import AhbSlave           :: *;
import ApbAddrMap         :: *;
import ApbSlave           :: *;
import BlueAddrMap        :: *;
import BlueCSRAPBAdapter  :: *;
import BlueCSRCore        :: *;
import BlueCSRFabricMap   :: *;
import BlueCSRSoC         :: *;
import ExamplePeripherals :: *;

typedef AhbSlaveFabric_ifc#(32, 32)    AhbPort_t;
typedef ApbSlaveFabric_ifc#(32, 32, 0) ApbPort_t;

interface PeripheralIO_ifc;
    interface ExampleUart_ifc uart0;
    interface ExampleUart_ifc uart1;

    method Bool timer_irq;
endinterface

interface ExampleSoC_ifc;
    interface AhbPort_t       ahb;
    interface PeripheralIO_ifc peripherals;
endinterface

module mkScratchMemory(AhbPort_t);
    AhbSlave_ifc#(32, 32) i_slave <- mkAhbSlave(True);
    Reg#(Bit#(32))       rg_word <- mkReg(0);

    rule r_access;
        let req <- i_slave.request.get;
        if(req.write) rg_word <= req.write_data;
        i_slave.response.put(AhbResponse_t { read_data: rg_word, slave_error: False });
    endrule

    return i_slave.fabric;
endmodule

module [Module] mkPeripheralAPBPort#(BlueCSR_ifc#(32, 32, ni) csr)(ApbPort_t);
    BlueCSR_APB_ifc#(32, 32, 0, ni) i_apb <- mkBlueCSRAPBAdapter(csr, True);
    return i_apb.s_apb;
endmodule

module [FabricMapCtx_t#(32, ApbPort_t)] peripheral_map(PeripheralIO_ifc);
    addr_map_def("peripherals");

    BlueCSRFabricTarget_ifc#(0, ExampleUart_ifc) i_uart0 <- bluecsr_fabric_target('h1000, 'h1000, "uart0", uart_registers,  defaultValue, mkPeripheralAPBPort);
    BlueCSRFabricTarget_ifc#(0, ExampleUart_ifc) i_uart1 <- bluecsr_fabric_target('h2000, 'h1000, "uart1", uart_registers,  defaultValue, mkPeripheralAPBPort);
    BlueCSRFabricTarget_ifc#(1, Empty)           i_timer <- bluecsr_fabric_target('h3000, 'h1000, "timer", timer_registers, defaultValue, mkPeripheralAPBPort);

    interface uart0     = i_uart0.internal;
    interface uart1     = i_uart1.internal;
    method    timer_irq = i_timer.irqs[0];
endmodule

module [FabricMapCtx_t#(32, AhbPort_t)] soc_map(PeripheralIO_ifc);
    addr_map_def("Example SoC");

    AhbPort_t i_scratch <- liftModule(mkScratchMemory);
    fabric_target('h0000_0000, 4, "scratch", i_scratch);

    ApbBusCfg_t apb_cfg = defaultValue;
    apb_cfg.local_addr = True;

    AddrMapSubBus_ifc#(3, PeripheralIO_ifc) i_apb <- fabric_bridge('h4000_0000, 'h0001_0000, "apb", apb_cfg, peripheral_map);

    return i_apb.internal;
endmodule

typedef AddrMapBus_ifc#(2, AhbPort_t, PeripheralIO_ifc) ExampleSoCBus_t;

function AhbBusCfg_t example_ahb_config();
    AhbBusCfg_t cfg = defaultValue;
    cfg.local_addr = True;
    return cfg;
endfunction

function ExampleSoC_ifc example_soc_ports(ExampleSoCBus_t i_fabric);
    return interface ExampleSoC_ifc;
        interface ahb         = i_fabric.up;
        interface peripherals = i_fabric.internal;
    endinterface;
endfunction

module [Module] mkBlueCSRSoC(ExampleSoC_ifc);
    ExampleSoCBus_t i_fabric <- create_fabric(example_ahb_config(), soc_map);
    return example_soc_ports(i_fabric);
endmodule

endpackage
