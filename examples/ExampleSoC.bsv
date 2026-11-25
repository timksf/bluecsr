package ExampleSoC;

import BuildVector  :: *;
import DefaultValue :: *;
import GetPut       :: *;
import RegFile      :: *;
import Vector       :: *;

import Ahb                :: *;
import AhbAddrMap         :: *;
import AhbSlave           :: *;
import ApbAddrMap         :: *;
import ApbSlave           :: *;
import BlueAddrMap        :: *;
import BlueCSRAHBAdapter  :: *;
import BlueCSRSoC         :: *;
import ExamplePeripherals :: *;

typedef AhbSlaveFabric_ifc#(32, 32)    AhbPort_t;
typedef ApbSlaveFabric_ifc#(32, 32, 0) ApbPort_t;

interface PeripheralIO_ifc;
    interface ExampleUart_ifc uart0;
    interface ExampleUart_ifc uart1;
    interface ExampleGpio_ifc gpio;

    method Bool timer_irq;
    method Bool gpio_irq;
endinterface

interface SocDevices_ifc;
    interface PeripheralIO_ifc peripherals;

    method Bool irq;
endinterface

interface ExampleSoC_ifc;
    interface AhbPort_t        ahb;
    interface PeripheralIO_ifc peripherals;

    method Bool irq;    //CPU interrupt from the system controller
endinterface

/* memories */

//read-only boot memory, writes fail
module mkBootRom(AhbPort_t);
    AhbSlave_ifc#(32, 32) i_slave <- mkAhbSlave(True);

    function Bit#(32) rom_word(Bit#(32) address);
        case(address[11:2])
            0:       return 'h2000_1000;    //initial stack pointer, top of SRAM
            1:       return 'h0000_0101;    //reset vector
            default: return 0;
        endcase
    endfunction

    rule r_access;
        let req <- i_slave.request.get;
        i_slave.response.put(AhbResponse_t { read_data: rom_word(req.address), slave_error: req.write });
    endrule

    return i_slave.fabric;
endmodule

//4 KiB of byte addressable memory
module mkSram(AhbPort_t);
    AhbSlave_ifc#(32, 32)        i_slave <- mkAhbSlave(True);
    RegFile#(Bit#(10), Bit#(32)) i_mem   <- mkRegFileFull;

    function Bit#(8) lane_mask(Bit#(1) strobe) = signExtend(strobe);

    rule r_access;
        let      req   <- i_slave.request.get;
        Bit#(10) index =  req.address[11:2];
        Bit#(32) word  =  i_mem.sub(index);

        if(req.write) begin
            Vector#(4, Bit#(1)) lanes = unpack(ahb_to_bluecsr_strobe(req.address, req.size));
            Bit#(32)            mask  = pack(map(lane_mask, lanes));
            i_mem.upd(index, (word & ~mask) | (req.write_data & mask));
        end
        i_slave.response.put(AhbResponse_t { read_data: word, slave_error: False });
    endrule

    return i_slave.fabric;
endmodule

/*
 * The AHB segment holds the boot ROM, the SRAM and the system controller, and bridges a 64 KiB window to
 * the APB segment with two UARTs, the timer and the GPIO. Both segments pass window offsets to their
 * targets. The system controller combines the peripheral interrupts into the CPU interrupt.
 */

module [AddrMapCtx_t#(32, ApbPort_t)] peripheral_map(PeripheralIO_ifc);
    addr_map_def("peripherals");

    BlueCSRTarget_ifc#(0, ExampleUart_ifc) i_uart0 <- csr_addr_map_target('h1000, 'h1000, "uart0", uart_registers);
    BlueCSRTarget_ifc#(0, ExampleUart_ifc) i_uart1 <- csr_addr_map_target('h2000, 'h1000, "uart1", uart_registers);
    BlueCSRTarget_ifc#(1, Empty)           i_timer <- csr_addr_map_target('h3000, 'h1000, "timer", timer_registers);
    BlueCSRTarget_ifc#(1, ExampleGpio_ifc) i_gpio  <- csr_addr_map_target('h4000, 'h1000, "gpio",  gpio_registers);

    interface uart0     = i_uart0.internal;
    interface uart1     = i_uart1.internal;
    interface gpio      = i_gpio.internal;
    method    timer_irq = i_timer.irqs[0];
    method    gpio_irq  = i_gpio.irqs[0];
endmodule

module [AddrMapCtx_t#(32, AhbPort_t)] soc_map(SocDevices_ifc);
    addr_map_def("Example SoC");

    ApbBusCfg_t apb_cfg = defaultValue;
    apb_cfg.local_addr = True;

    AhbPort_t                               i_rom  <- addr_map_device('h0000_0000, 'h1000, "rom",  mkBootRom, id);
    AhbPort_t                               i_sram <- addr_map_device('h2000_0000, 'h1000, "sram", mkSram,    id);
    AddrMapSubBus_ifc#(4, PeripheralIO_ifc) i_apb  <- addr_map_bridge('h4000_0000, 'h0001_0000, "apb", apb_cfg, peripheral_map);

    let io          = i_apb.internal;
    let irq_sources = vec(io.timer_irq, io.gpio_irq, io.uart0.rx_ready, io.uart1.rx_ready);

    BlueCSRTarget_ifc#(0, ExampleSysCtrl_ifc) i_sysctrl <- csr_addr_map_target('h1000_0000, 'h1000, "sysctrl", sysctrl_registers(irq_sources));

    interface peripherals = io;
    method    irq         = i_sysctrl.internal.irq;
endmodule

typedef AddrMapBus_ifc#(4, AhbPort_t, SocDevices_ifc) ExampleSoCBus_t;

function AhbBusCfg_t example_ahb_config();
    AhbBusCfg_t cfg = defaultValue;
    cfg.local_addr = True;
    return cfg;
endfunction

module [Module] mkBlueCSRSoC(ExampleSoC_ifc);
    ExampleSoCBus_t i_fabric <- create_addr_map_bus_cfg(example_ahb_config(), soc_map);

    interface ahb         = i_fabric.up;
    interface peripherals = i_fabric.internal.peripherals;
    method    irq         = i_fabric.internal.irq;
endmodule

endpackage
