#for BSVTools
ifndef BLUECSR_MK_INCLUDED
BLUECSR_MK_INCLUDED := 1

BLUECSR_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BLUECSR_SRC  := $(BLUECSR_ROOT)/src

include $(BLUECSR_ROOT)/dep/bluefabric/BlueFabric.mk

EXTRA_BSV_LIBS += $(BLUECSR_SRC)

$(info Adding BlueCSR from $(BLUECSR_SRC))

endif