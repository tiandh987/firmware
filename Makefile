# buildroot 版本
BR_VER = 2023.02.7

# make -C $(PWD)/output/buildroot-2023.02.7 BR2_EXTERNAL=$(PWD)/general O=$(PWD)/output
#   -C            指定了 make 命令的工作目录
#   BR2_EXTERNAL  设置 Buildroot 的外部配置目录
#   O             设置 Buildroot 的输出目录
BR_MAKE = $(MAKE) -C $(TARGET)/buildroot-$(BR_VER) BR2_EXTERNAL=$(PWD)/general O=$(TARGET)

# buildroot 链接地址
BR_LINK = https://github.com/buildroot/buildroot/archive

# 将 buildroot 保存到该地址
BR_FILE = /tmp/buildroot-$(BR_VER).tar.gz

# ?= 表示如果该变量没有被赋值，则赋予等号后的值
TARGET ?= $(PWD)/output

# 为 CONFIG 变量赋值
# $(error ...) 产生一个致命错误
CONFIG = $(error variable BOARD is not defined)

# 记录当前时间
# %s  seconds since 1970-01-01 00:00:00 UTC
TIMER := $(shell date +%s)

ifeq ($(MAKECMDGOALS),all)
ifeq ($(BOARD),)
LIST := $(shell find ./br-ext-*/configs/*_defconfig | sort | \
	sed -E "s/br-ext-chip-(.+).configs.(.+)_defconfig/'\2' '\1 \2'/")
BOARD := $(or $(shell whiptail --title "Available boards" --menu "Please select a board:" 20 76 12 \
	--notags $(LIST) 3>&1 1>&2 2>&3),$(CONFIG))
endif
endif

# 比较 BOARD 的值是否不为空，不为空返回 true。
# 例如 BOARD 为 hi3518ev200_ultimate
ifneq ($(BOARD),)
# 为 CONFIG 赋值
# grep -m1 的作用是：在匹配到第一个符合条件的行后停止搜索，即只匹配文件的前几行。
#   这个参数的主要用途是在大文件中进行搜索时，可以加速查找过程，特别是当你只关心找到的第一个匹配行时。
#
# CONFIG 为 br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig
CONFIG := $(shell find br-ext-*/configs/*_defconfig | grep -m1 $(BOARD))
# include 用于引入其它 makefile 文件
# 引入  br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig 文件的内容 
include $(CONFIG)
endif

help:
	@printf "BR-OpenIPC usage:\n \
	- make list - show available device configurations\n \
	- make deps - install build dependencies\n \
	- make clean - remove defconfig and target folder\n \
	- make package - list available packages\n \
	- make distclean - remove buildroot and output folder\n \
	- make br-linux - build linux kernel only\n \
	- make all - build the device firmware\n\n"

all: build repack timer

# make -C $(PWD)/output/buildroot-2023.02.7 BR2_EXTERNAL=$(PWD)/general O=$(PWD)/output all
#   -C            指定了 make 命令的工作目录
#   BR2_EXTERNAL  设置 Buildroot 的外部配置目录
#   O             设置 Buildroot 的输出目录
#   all           执行 make all 操作
build: defconfig
	@$(BR_MAKE) all

br-%: defconfig
	@$(BR_MAKE) $(subst br-,,$@)

# 在执行 defconfig 之前，先执行 prepare 目标。
#
# 使用 echo 命令输出 ---，然后使用 Makefile 的 $(or ...) 函数检查是否存在变量 CONFIG。
#   如果不存在，则使用 $(error ...) 函数输出错误信息；
#
# echo 输出： --- br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig
#
# make -C $(PWD)/output/buildroot-2023.02.7 BR2_EXTERNAL=$(PWD)/general O=$(PWD)/output BR2_DEFCONFIG=$(PWD)/br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig defconfig
#   -C            指定了 make 命令的工作目录
#   BR2_EXTERNAL  设置 Buildroot 的外部配置目录
#   O             设置 Buildroot 的输出目录
#   BR2_DEFCONFIG 设置 Buildroot 的默认配置文件，即指定使用哪个配置文件来进行构建
#   defconfig     执行 make defconfig 操作
defconfig: prepare
	@echo --- $(or $(CONFIG),$(error variable BOARD is not found))
	@$(BR_MAKE) BR2_DEFCONFIG=$(PWD)/$(CONFIG) defconfig

# 检查目录 ${PWD}/output/buildroot-2023.02.7 是否存在
# 如果不存在，下载 buildroot 源码，然后解压到 $(TARGET) 目录
#
# wget 命令下载 https://github.com/buildroot/buildroot/archive/2023.02.7.tar.gz，保存到 /tmp/buildroot-2023.02.7.tar.gz
#   -c 表示断点续传，-q 表示安静模式，不显示下载进度，-O $(BR_FILE) 表示将下载的文件保存为指定的文件名。
#
# 创建文件夹 ${PWD}/output
# 解压下载的 buildroot 压缩包到 ${PWD}/output 目录
prepare:
	@if test ! -e $(TARGET)/buildroot-$(BR_VER); then \
		wget -c -q $(BR_LINK)/$(BR_VER).tar.gz -O $(BR_FILE); \
		mkdir -p $(TARGET); tar -xf $(BR_FILE) -C $(TARGET); fi

toolname:
	@general/scripts/show_toolchains.sh $(CONFIG)

package:
	@find general/package/* -maxdepth 0 -type d -printf "br-%f\n" | grep -v patch

clean:
	@rm -rf $(TARGET)/images $(TARGET)/target

distclean:
	@rm -rf $(BR_FILE) $(TARGET)

list:
	@ls -1 br-ext-chip-*/configs

deps:
	sudo apt-get install -y automake autotools-dev bc build-essential cpio \
		curl file fzf git libncurses-dev libtool lzop make rsync unzip wget

# 用于输出构建过程的耗时
# 当前时间 - TIMER
# 
# 输出：- Build time: 00:00
timer:
	@echo - Build time: $(shell date -d @$(shell expr $(shell date +%s) - $(TIMER)) -u +%M:%S)

# 用于重新打包固件
repack:
ifeq ($(BR2_TARGET_ROOTFS_SQUASHFS),y)                            # BR2_TARGET_ROOTFS_SQUASHFS 是否等于 y
ifeq ($(BR2_OPENIPC_FLASH_SIZE),"8")                              # BR2_OPENIPC_FLASH_SIZE 是否等于 8
	@$(call PREPARE_REPACK,uImage,2048,rootfs.squashfs,5120,nor)
else
	@$(call PREPARE_REPACK,uImage,2048,rootfs.squashfs,8192,nor)
endif
endif

ifeq ($(BR2_TARGET_ROOTFS_UBI),y)                                 # BR2_TARGET_ROOTFS_UBI 是否等于 y
ifeq ($(BR2_OPENIPC_SOC_VENDOR),"rockchip")                       # BR2_OPENIPC_SOC_VENDOR 是否等于 "rockchip"
	@$(call PREPARE_REPACK,zboot.img,4096,rootfs.ubi,16384,nand)
else ifeq ($(BR2_OPENIPC_SOC_VENDOR),"sigmastar")                 # BR2_OPENIPC_SOC_VENDOR 是否等于 "sigmastar"
	@$(call PREPARE_REPACK,,,rootfs.ubi,16384,nand)
else
	@$(call PREPARE_REPACK,uImage,4096,rootfs.ubi,16384,nand)
endif
endif

ifeq ($(BR2_TARGET_ROOTFS_INITRAMFS),y)                           # BR2_TARGET_ROOTFS_INITRAMFS 是否等于 y
	@$(call PREPARE_REPACK,uImage,16384,,,initramfs)
endif

# 做打包前的准备工作
#
# 检查 内核镜像文件大小
# 检查 根文件系统文件大小
# 打包固件
define PREPARE_REPACK
	$(if $(1),$(call CHECK_SIZE,$(1),$(2)))
	$(if $(3),$(call CHECK_SIZE,$(3),$(4)))
	$(call REPACK_FIRMWARE,$(1),$(3),$(5))
endef

# 定义了一个名为 CHECK_SIZE 的宏，用于检查文件大小是否符合预期。
#
# FILE_SIZE 获取文件大小，单位 KB
#   stat 展示文件或文件系统的状态
#     -c 使用指定的格式而不是默认的格式；
#     %s 总大小，以字节为单位;
#
# 如果 FILE_SIZE 等于 0，退出
#
# echo 打印文件名称 $(1)，实际文件大小，期望文件大小
#
# 如果 实际文件大小 > 期望文件大小，打印超出了多少 kb，然后退出
define CHECK_SIZE
	$(eval FILE_SIZE = $(shell expr $(shell stat -c %s $(TARGET)/images/$(1) || echo 0) / 1024))
	if test $(FILE_SIZE) -eq 0; then exit 1; fi
	echo - $(1): [$(FILE_SIZE)KB/$(2)KB]
	if test $(FILE_SIZE) -gt $(2); then \
		echo -- size exceeded by: $(shell expr $(FILE_SIZE) - $(2))KB; exit 1; fi
endef

# 打包固件
#
# 创建目录 $(PWD)/output/images/$(3)
# 切换到目录 $(PWD)/output/images/$(3) && 拷贝内核镜像文件 
# 切换到目录 $(PWD)/output/images/$(3) && 拷贝根文件系统文件
# 切换到目录 $(PWD)/output/images/$(3) && 计算内核镜像文件的 md5 值
# 切换到目录 $(PWD)/output/images/$(3) && 计算根文件系统文件的 md5 值
# 如果第一个文件非空，则设置 KERNEL 变量为第一个文件及其 MD5 校验和，否则设置为空
# 如果第二个文件非空，则设置 ROOTFS 变量为第二个文件及其 MD5 校验和，否则设置为空
# 设置一个压缩包的名称 ARCHIVE
# 进入目标目录 并 将指定的文件和变量打包成一个压缩包
# 删除临时目录
define REPACK_FIRMWARE
	mkdir -p $(TARGET)/images/$(3)
	$(if $(1),cd $(TARGET)/images/$(3) && cp -f ../$(1) $(1).$(BR2_OPENIPC_SOC_MODEL))
	$(if $(2),cd $(TARGET)/images/$(3) && cp -f ../$(2) $(2).$(BR2_OPENIPC_SOC_MODEL))
	$(if $(1),cd $(TARGET)/images/$(3) && md5sum $(1).$(BR2_OPENIPC_SOC_MODEL) > $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(2),cd $(TARGET)/images/$(3) && md5sum $(2).$(BR2_OPENIPC_SOC_MODEL) > $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum)
	$(if $(1),$(eval KERNEL = $(1).$(BR2_OPENIPC_SOC_MODEL) $(1).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval KERNEL =))
	$(if $(2),$(eval ROOTFS = $(2).$(BR2_OPENIPC_SOC_MODEL) $(2).$(BR2_OPENIPC_SOC_MODEL).md5sum),$(eval ROOTFS =))
	$(eval ARCHIVE = ../openipc.$(BR2_OPENIPC_SOC_MODEL)-$(3)-$(BR2_OPENIPC_FLAVOR).tgz)
	cd $(TARGET)/images/$(3) && tar -czf $(ARCHIVE) $(KERNEL) $(ROOTFS)
	rm -rf $(TARGET)/images/$(3)
endef
