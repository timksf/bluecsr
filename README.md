BlueCSR defines synthesizable CSR maps in Bluespec and can export the same
metadata as readable documentation or SystemRDL.


#### Interrupt outputs

`csr_irq` turns an event strobe into a sticky W1C pending field and combines it
with an RW enable field. `create_blue_csr` ORs each enabled pending source onto
its selected `IRQLines_ifc` output, so multiple fields may safely share a line
and one CSR block may expose multiple lines.

#### Access execution model

Ordinary fields contribute combinational read values and simple write actions.
Those contributions are composed at each register offset. Side-effecting or
fallible accesses, such as FIFO dequeue/enqueue, use a separate scheduled
`ActionValue` path. This split is internal to map construction and is required
for correct Bluespec scheduling; normal users should use the field, FIFO, and
region constructors below rather than creating operation entries directly.

With `create_blue_csr`, requests in a direction unsupported by a register or
region return `CSR_DECERR`. A side-effecting handler can return a more specific
response such as `CSR_SLVERR` when a mapped operation is temporarily
unavailable.

`create_blue_csr` returns `CSR_DECERR` whenever no more-specific access rule
can fire. `create_blue_csr_with_default_response` can select a different
fallback response. The configured response also applies to a mapped
entry when its direction or policy has no applicable rule. Maps that need a
different result should add an explicit handler for that access.

#### Bluespec API
- `BlueCSRCtx_t` collection context used to build a CSR map and return internal module state.
- `csr_regmap_def` adds the top-level CSR map name and description.
- `csr_reg_def` declares a register at a byte offset.
- `csr_reg_prot` sets read and write access policy for a single register-sized entry.
- `csr_region_def` declares a memory-like region at a byte offset with a byte length.
- `csr_region_prot` sets read and write access policy for a region.

Field definitions:
- `csr_reg_field` generic field constructor for any `BlueCSRAccess_t` mode.
- `csr_reg_hu` creates a hardware-updatable field whose readable state remains
  owned by BlueCSR. Software writes use ordinary field semantics, while a
  same-cycle hardware `update` takes priority.
- `csr_reg_rw` creates a read-write field backed by a register.
- `csr_reg_ro` creates a read-only field backed by a register.
- `csr_reg_rc` creates a read-constant field with a fixed value.
- `csr_reg_wo` creates a write-only field.
- `csr_reg_ws` creates a write-set field.
- `csr_reg_wc` creates a write-clear field.
- `csr_reg_w1c` creates a single-bit write-1-to-clear field with a Boolean hardware event input that takes priority over software clearing.
- `csr_reg_w1c_evt_reg` is the same event field and returns its pending-state register for hardware use.
- `csr_irq` creates an event-latched W1C pending field and its RW enable field, then contributes `pending && enable` to a selected external IRQ line. Multiple fields may OR onto one line, and one map may drive multiple lines.
- `csr_reg_w1s` creates a write-1-to-set field.
- `csr_reg_fifo_ro` creates an exclusive, LSB-aligned FIFO read that returns `CSR_SLVERR` when empty. FIFO widths must be byte multiples no wider than the CSR data width.
- `csr_reg_fifo_ro_valid` creates a non-failing FIFO read with byte-multiple data at the least-significant bits and a valid bit immediately above it. The FIFO element width plus one must fit in the CSR data width.
- `csr_reg_fifo_wo` creates an exclusive, LSB-aligned FIFO write that accepts exactly the byte strobes occupied by the FIFO field and returns `CSR_SLVERR` when full. FIFO widths must be byte multiples no wider than the CSR data width.

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
- `create_blue_csr` builds the live BlueCSR interface from a `BlueCSRCtx_t` definition. Its inferred `ni` parameter configures the external IRQ vector width.
- `create_blue_csr_with_default_response` builds the same interface and lets
  the caller choose the response when no more-specific access rule can fire.
  The legacy constructor remains equivalent to selecting `CSR_DECERR`.
- `doc_blue_csr` renders a human-readable register map summary.
- `doc_blue_csr_markdown` renders the register map as a Markdown table.
- `export_systemrdl_blue_csr` writes the register map out as SystemRDL.

Interfaces and types:
- `IRQLines_ifc#(n)` is the shared vector subinterface whose `lines` method returns `Vector#(n, Bool)`.
- `BlueCSR_ifc#(aw, dw, ni)` contains request and response interfaces plus `IRQLines_ifc#(ni) irqs`.
- `BlueCSRAccess_ifc` bundle containing the external CSR interface and the internal user interface.
- `BlueCSR_Req_t` request payload type.
- `BlueCSR_Rsp_t` response payload type.
- `BlueCSRResponse_t` response status enum: `CSR_OKAY`, `CSR_EXOKAY`, `CSR_SLVERR`, `CSR_DECERR`.
- `BlueCSRAccess_t` field access enum: `CSR_RW`, `CSR_RO`, `CSR_RC`, `CSR_WC`, `CSR_WS`, `CSR_WO`, `CSR_W1S`, `CSR_W1C`.
- `BlueCSRProt_t` security attribute enum: `CSR_SECURE` or `CSR_INSECURE`.
- `BlueCSRTrigger_t` trigger mode enum: `TRIG_RO`, `TRIG_WO`, `TRIG_RW`.

AXI4-Lite adapter API:
- `mkBlueCSRAXI4LiteAdapter` bridges a `BlueCSR_ifc` instance to AXI4-Lite slave read and write channels.
- `BlueCSR_AXI4Lite_ifc#(aw, dw, ni)` contains the AXI4-Lite read/write slave interfaces and forwards the same `irqs` vector subinterface.
