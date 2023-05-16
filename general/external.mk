EXTERNAL_FAMILY = $(shell grep -oE "board.\w+" $(BR2_CONFIG) | cut -d "/" -f 2)
EXTERNAL_RELEASE = $(shell grep -oE "\w+_defconfig" $(BR2_CONFIG) | cut -d "_" -f 2)
EXTERNAL_VENDOR = $(shell grep -oE "br-ext-chip-\w+" $(BR2_CONFIG))

export BR2_EXTERNAL_VENDOR = $(BR2_EXTERNAL)/../$(EXTERNAL_VENDOR)
export BR2_EXTERNAL_SCRIPTS = $(BR2_EXTERNAL)/scripts

include $(BR2_EXTERNAL)/linux/linux-ext-vendor-patcher.mk
include $(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk))
