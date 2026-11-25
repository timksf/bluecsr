package ExampleSoCDoc;

import BlueAddrMap :: *;

import ExampleSoC :: *;

//writes the SystemRDL export of the example SoC while bsc elaborates this top, nothing is simulated
(* synthesize *)
module mkExampleSoCDoc(Empty);
    export_addr_map_systemrdl("sim/ExampleSoC.rdl", example_ahb_config(), soc_map);
endmodule

endpackage
