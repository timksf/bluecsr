#for BSVTools
ifndef BLUECSR_MK_INCLUDED
BLUECSR_MK_INCLUDED := 1

BLUECSR_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BLUECSR_SRC  := $(BLUECSR_ROOT)/src

# Prefer the project's library, falling back to the bundled dependency.
BLUECSR_BLUEFABRIC_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueFabric.mk) $(BLUECSR_ROOT)/dep/bluefabric/BlueFabric.mk)
include $(BLUECSR_BLUEFABRIC_MK)

EXTRA_BSV_LIBS += $(BLUECSR_SRC)

$(info Adding BlueCSR from $(BLUECSR_SRC))

endif
