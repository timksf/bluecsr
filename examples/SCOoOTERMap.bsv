package SCOoOTERMap;

import BuildVector :: *;
import Vector :: *;

import AddrMapDecoder :: *;
import BlueAddrMap :: *;
import BlueInterruptMap :: *;
import BlueCSRCore :: *;

import Interfaces :: *;
import SCOoOTERMapSupport :: *;

module [AddrMapCtx_t#(32, MemMappedIFC#(32))] scoooter_address_map(SCOoOTERDevices_ifc);
    addr_map_def("SCOoOTER");

    SCOoOTERDevices_ifc i_devices <- mkSCOoOTERDevices;

    //                              base          size          name               target
    addr_map_target('h0001_0000, 'h0001_0000, "SPI_MEMORY",      i_devices.spi_memory.memory_bus);
    addr_map_target('h1100_0000, 'h0001_0000, "RV_CONTROLLER",   i_devices.rv_controller);
    addr_map_target('h1200_0000, 'h0000_1000, "BLUECSR_STUB",    i_devices.bluecsr_stub.memory_bus);
    addr_map_target('h1200_1000, 'h0000_1000, "SPI_CONTROL",     i_devices.spi_memory.control_bus);
    addr_map_target('h4000_0000, 'h0000_1000, "CLINT",           i_devices.clint);
    addr_map_target('h5000_0000, 'h0040_0000, "PLIC",            i_devices.plic);
    addr_map_target('h8000_0000, 'h1000_0000, "AXI_FULL_WINDOW", i_devices.axi_full);
    addr_map_target('hA000_0000, 'h1000_0000, "AXI_LITE_WINDOW", i_devices.axi_lite);

    return i_devices;
endmodule

module [IRQMapCtx_t#(4)] scoooter_irq_map#(SCOoOTERDevices_ifc devices)(Empty);
    irq_map_def("SCOoOTERPLIC");

    //                          base  name              source vector
    irq_map_source(0, "PLATFORM_IRQS", devices.platform_irqs);
    irq_map_source(2, "EXPANSION_IRQ", vec(devices.expansion_irq));
    irq_map_source(3, "BLUECSR_STUB",  devices.bluecsr_stub.irqs);
endmodule

interface SCOoOTERMap_ifc;
    interface AddrMapDecoder_ifc#(32) decoder;
    method Vector#(4, Bool) irqs;
    interface SCOoOTERDevices_ifc devices;
endinterface

// The protocol-specific fabric generator consumes decoder and devices. The
// IRQ output is already positioned and OR-combined for direct PLIC connection.
// CPU software, timer, and external interrupt channels remain explicit.
module mkSCOoOTERMap(SCOoOTERMap_ifc);
    AddrMap_ifc#(32, SCOoOTERDevices_ifc) i_address_map <- create_addr_map(scoooter_address_map);
    IRQMap_ifc#(4, Empty)                 i_irq_map     <- create_irq_map(scoooter_irq_map(i_address_map.internal));

    interface decoder = i_address_map.decoder;
    method irqs       = i_irq_map.irqs;
    interface devices = i_address_map.internal;
endmodule

endpackage
