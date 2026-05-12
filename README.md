WIP..

Goal: Generic CSR definition from bluespec code with optional
export to some form of structured format.

#### Bluespec API
- `BlueCSRCtx_t` collection context used to build a CSR map and return internal module state.
- `csr_regmap_def` adds the top-level CSR map name and description.
- `csr_reg_def` declares a register at a byte offset.
- `csr_reg_prot` sets read and write access policy for a single register-sized entry.
- `csr_region_def` declares a memory-like region at a byte offset with a byte length.
- `csr_region_prot` sets read and write access policy for a region.

Field definitions:
- `csr_reg_field` generic field constructor for any `BlueCSRAccess_t` mode.
- `csr_reg_rw` creates a read-write field backed by a register.
- `csr_reg_ro` creates a read-only field backed by a register.
- `csr_reg_rc` creates a read-constant field with a fixed value.
- `csr_reg_wo` creates a write-only field.
- `csr_reg_ws` creates a write-set field.
- `csr_reg_wc` creates a write-clear field.
- `csr_reg_w1c` creates a write-1-to-clear field.
- `csr_reg_w1s` creates a write-1-to-set field.

Region accessors:
- `csr_region_ro` creates a read-only region backed by a read function.
- `csr_region_wo` creates a write-only region backed by a write function.
- `csr_region_rw` creates a read-write region backed by read and write functions.

Trigger fields:
- `csr_reg_trig` creates a generic trigger bit on read, write, or both, with optional delayed pulse generation.
- `csr_reg_trigr` creates a trigger bit that pulses on reads.
- `csr_reg_trigw` creates a trigger bit that pulses on writes.
- `csr_reg_trigrw` creates a trigger bit that pulses on reads and writes.

Runtime and export:
- `create_blue_csr` builds the live BlueCSR interface from a `BlueCSRCtx_t` definition.
- `doc_blue_csr` renders a human-readable register map summary.
- `export_systemrdl_blue_csr` writes the register map out as SystemRDL.

Interfaces and types:
- `BlueCSR_ifc` request and response interface for the transactional CSR bus.
- `BlueCSRAccess_ifc` bundle containing the external CSR interface and the internal user interface.
- `BlueCSR_Req_t` request payload type.
- `BlueCSR_Rsp_t` response payload type.
- `BlueCSRResponse_t` response status enum: `CSR_OKAY`, `CSR_EXOKAY`, `CSR_SLVERR`, `CSR_DECERR`.
- `BlueCSRAccess_t` field access enum: `CSR_RW`, `CSR_RO`, `CSR_RC`, `CSR_WC`, `CSR_WS`, `CSR_WO`, `CSR_W1S`, `CSR_W1C`.
- `BlueCSRProt_t` security attribute enum: `CSR_SECURE` or `CSR_INSECURE`.
- `BlueCSRTrigger_t` trigger mode enum: `TRIG_RO`, `TRIG_WO`, `TRIG_RW`.

AXI4-Lite adapter API:
- `mkBlueCSRAXI4LiteAdapter` bridges a `BlueCSR_ifc` instance to AXI4-Lite slave read and write channels.
- `BlueCSR_AXI4Lite_ifc` AXI4-Lite slave-facing interface returned by the adapter.
