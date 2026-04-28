WIP..

Goal: Generic CSR definition from bluespec code with optional
export to some form of structured format.

#### Bluespec API
- `csr_regmap_def` for module name and description
- `csr_reg_def` for register definition at offset
- `csr_region_def` for register region definition at offset with length
- `csr_reg_prot` for access protection definition of register at offset
- `csr_region_prot` for region protection definition of region at offset with length

Field definitions:
- `csr_reg_rc` for constant field
- `csr_reg_rw` for read-write field
- `csr_reg_w1c` for write-1-to-clear field
- `csr_reg_w1s` for write-1-to-set field
- `csr_region_ro` for read-only region
- `csr_region_wo` for write-only region
- `csr_region_rw` for read-write region