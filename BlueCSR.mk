#for BSVTools
ifndef BLUECSR_MK_INCLUDED
BLUECSR_MK_INCLUDED := 1

BLUECSR_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BLUECSR_SRC  := $(BLUECSR_ROOT)/src

# Prefer the project's library, falling back to the bundled dependency.
BLUECSR_BLUEFABRIC_MK := $(firstword $(wildcard \
    $(CURDIR)/libraries/*/BlueFabric.mk $(CURDIR)/libraries/*/bluefabric.mk \
    $(BLUECSR_ROOT)/dep/bluefabric/BlueFabric.mk $(BLUECSR_ROOT)/dep/bluefabric/bluefabric.mk))
# BlueCSRCore can also be used without the optional bus adapters.
ifneq ($(BLUECSR_BLUEFABRIC_MK),)
include $(BLUECSR_BLUEFABRIC_MK)
endif

EXTRA_BSV_LIBS += $(BLUECSR_SRC)

$(info Adding BlueCSR from $(BLUECSR_SRC))

endif
