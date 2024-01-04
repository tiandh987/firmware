#!/bin/bash
#
# OpenIPC.org (c)
#

#
# Constants
#

MAX_KERNEL_SIZE=0x200000              #    2MiB,  2097152
MAX_KERNEL_SIZE_ULTIMATE=0x300000     #    3MiB,  3145728
MAX_KERNEL_SIZE_EXPERIMENTAL=0x3E8480 # ~3.9MiB,  4097152
MAX_ROOTFS_SIZE=0x500000              #    5MiB,  5242880
MAX_ROOTFS_SIZE_ULTIMATE=0xA00000     #   10MiB, 10485760

# 年月日 例如：_d=24.01.03
_d=$(date +"%y.%m.%d")

# 版本 例如：OPENIPC_VER='OpenIPC v2.4.01.03'
OPENIPC_VER=$(echo OpenIPC v${_d:0:1}.${_d:1})

unset _d

SRC_CACHE_DIR="/tmp/buildroot_dl"
LOCK_FILE="$(pwd)/openipc.lock"

#
# Functions
#

# 带颜色输出的 echo
echo_c() {
  # 30 grey, 31 red, 32 green, 33 yellow, 34 blue, 35 magenta, 36 cyan,37 white
  echo -e "\e[1;$1m$2\e[0m"
}

# 检查 或者 设置锁文件
# 如果锁文件存在，检查是否有记录的进程号在运行，有则说明有其它实例正在运行，退出
# 如果锁文件不存在，则创建锁文件
check_or_set_lock() {
  # -f  判断文件是否存在
  #
  # \s  匹配任何不可见字符
  # *   匹配前面的子表达式任意次
  # \b  匹配一个单词的边界。例如，"er\b" 可以匹配 “never” 中的 “er”，但不能匹配 “verb” 中的 “er”；“\b1_” 可以匹配 “1_23” 中的 “1_”，但不能匹配 “21_3” 中的 “1_”。

  if [ -f "$LOCK_FILE" ] && ps -ax | grep "^\s*\b$(cat "$LOCK_FILE")\b" >/dev/null; then
    echo_c 31 "Another instance running with PID $(cat "$LOCK_FILE")."
    exit 1
  fi

  echo_c 32 "Starting OpenIPC builder."

  # $$  Shell 本身的 PID（ProcessID）
  echo $$ >$LOCK_FILE
}

# 项目的构建列表
build_list_of_projects() {
  # 初始化一个空数组
  FUNCS=()
  
  # 通过 find 命令，找到可用的项目（在 br-ext-chip-*/configs/* 目录中，找到名称匹配 "*_defconfig" 正则表达式的文件）
  AVAILABLE_PROJECTS=$(find br-ext-chip-*/configs/* -name "*_defconfig")

  local p
  for p in $AVAILABLE_PROJECTS; do
    # 从文件路径中提取出文件名，并去掉文件名中的 _defconfig 部分
    # ${p##*/}           参数扩展，它会删除变量 p 中最后一个斜杠（/）及其之前的部分
    # ${p//_defconfig/}  参数替换，它会将变量 p 中所有的 _defconfig 替换为空字符串
    #
    # 例如：br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig，将得到 hi3518ev200_ultimate
    p=${p##*/}; p=${p//_defconfig/}

    # 将变量 p 的值添加到名为 FUNCS 的数组中
    FUNCS+=($p)
  done
}

# 选择项目
select_project() {
  # $# 添加到 Shell 的参数个数
  if [ $# -eq 0 ]; then
    # command -v fzf 用于查找并输出 fzf 命令的路径。

    # 查找 fzf 命令的路径
    if [ -n "$(command -v fzf)" ]; then
      # echo $AVAILABLE_PROJECTS | sed "s/ /\n/g"
      #   将 $AVAILABLE_PROJECTS 变量的内容进行处理，将 空格 替换为 换行符，形成一个以换行符分隔的项目列表。
      #
      # fzf 
      #   这里使用 fzf 工具来进行交互式选择。用户可以从项目列表中选择一个或多个项目。
      local entries=$(echo $AVAILABLE_PROJECTS | sed "s/ /\n/g" | fzf)

      #  这一部分检查用户是否取消了选择。如果用户没有选择任何项目（即 $entries 为空），则输出 "Cancelled." 消息，并执行 drop_lock_and_exit 函数以退出脚本。
      [ -z "$entries" ] && echo_c 31 "Cancelled." && drop_lock_and_exit

      # 使用 cut 命令提取路径的第三个字段（使用 / 分割）
      # 使用 awk 命令进一步提取该字段的前两部分（使用 _ 分割），并使用下划线( _ )连接它们
      #
      # 例如： br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig
      BOARD=$(echo $entries | cut -d / -f 3 | awk -F_ '{printf "%s_%s", $1, $2}')

    # # 查找 whiptail 命令的路径  
    elif [ -n "$(command -v whiptail)" ]; then
      # 使用了 whiptail 命令创建一个菜单，让用户从可用的项目列表中进行交互式选择，并根据选择设置 BOARD 变量。

      # 定义了初始的 whiptail 命令，设置了对话框的标题和提示信息。
      local cmd="whiptail --title \"Available projects\" --menu \"Please select a project from the list:\" --notags 20 76 12"

      # 这是一个循环，用于遍历 $AVAILABLE_PROJECTS 列表中的每个项目
      local entry
      for entry in $AVAILABLE_PROJECTS; do
        # 从项目路径中提取出项目名称，并去掉 _defconfig 后缀
        #
        # 例如： br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig，得到 hi3518ev200_ultimate_defconfig
        local project=${entry##*/}; project=${project//_defconfig/}

        # 从项目路径中提取出供应商（vendor）的信息
        # ${entry%%/*} 表示从变量 entry 的末尾开始，删除 最长的匹配斜杠 / 及其后面的部分。这样，就得到了 entry 变量中第一个斜杠之前的内容。
        #
        # 例如： br-ext-chip-hisilicon/configs/hi3518ev200_ultimate_defconfig，得到 br-ext-chip-hisilicon，得到 hisilicon
        local vendor=${entry%%/*}; vendor=${vendor##*-}

        # 从项目名称中提取出风格（flavor）和芯片（chip）的信息。
        # # 例如：hi3518ev200_ultimate，得到 flavor 为 ultimate，得到 chip 为 hi3518ev200
        local flavor=${project##*_}
        local chip=${project%%_*}

        # 将项目的名称、供应商、芯片和风格信息添加到 whiptail 命令中
        cmd="${cmd} \"${project}\" \"${vendor^} ${chip^^} ${flavor}\""
      done

      # 使用 eval 执行构建好的 whiptail 命令，将用户的选择赋值给 BOARD 变量
      BOARD=$(eval "${cmd} 3>&1 1>&2 2>&3")

      # 检查 whiptail 命令的返回值，如果用户取消选择（返回值不为0），则输出取消消息并调用 drop_lock_and_exit 函数以退出脚本。
      [ $? != 0 ] && echo_c 31 "Cancelled." && drop_lock_and_exit

    else
      echo -ne "Usage: $0 <variant>\nVariants:"
      local i
      for i in "${FUNCS[@]}"; do echo -n " ${i}"; done
      echo
      drop_lock_and_exit
    fi
  else
    BOARD=$1
  fi
}

# 如果锁文件存在，删除锁文件，然后退出
drop_lock_and_exit() {
  [ -f "$LOCK_FILE" ] && rm $LOCK_FILE
  exit 0
}

# echo 打印命令，然后执行命令
log_and_run() {
  # 获取命令
  local command=$1

  # 打印命令
  echo_c 35 "$command"

  # 执行命令
  $command
}

clone() {
  sudo apt-get update -y
  sudo apt-get install -y automake make wget cpio file autotools-dev bc build-essential curl fzf git libtool rsync unzip libncurses-dev lzop
  git clone --depth=1 https://github.com/OpenIPC/firmware.git
}

fresh() {
  # buildroot 版本号
  BR_VER=2023.02.7

  # 检查是否存在指定的缓存目录 ($SRC_CACHE_DIR (/tmp/buildroot_dl))，
  if [ -d "$SRC_CACHE_DIR" ]; then
    echo_c 36 "Found cache directory."
  else
    echo_c 31 "Cache directory not found."
    echo_c 34 "Creating cache directory ..."
    # 如果不存在则创建
    log_and_run "mkdir -p ${SRC_CACHE_DIR}"
    echo_c 34 "Done.\n"
  fi

  # 检查是否存在指定版本的 Buildroot 目录 (buildroot-${BR_VER})。
  if [ -d "buildroot-${BR_VER}" ]; then
    echo_c 36 "Found existing Buildroot directory."

    # 如果存在，检查是否存在 Buildroot 下载目录 (buildroot-${BR_VER}/dl)
    if [ -d "buildroot-${BR_VER}/dl" ]; then
      echo_c 36 "Found existing Buildroot downloads directory."
      echo_c 34 "Copying Buildroot downloads to cache directory ..."
      # 如果存在则将下载的文件复制到缓存目录。
      log_and_run "cp -rvf buildroot-${BR_VER}/dl/* ${SRC_CACHE_DIR}"
      echo_c 34 "Done.\n"
    fi

    # 清理 Buildroot 源代码目录，执行 make distclean。
    echo_c 34 "Cleaning source directory."
    echo_c 35 "make distclean"
    make distclean
    echo_c 34 "Done.\n"
  else
    echo_c 31 "Buildroot sources not found."
  fi

  # 下载指定版本的 Buildroot 源代码到缓存目录（/tmp/buildroot_dl/buildroot-2023.02.7.tar.gz）
  echo_c 34 "Downloading Buildroot sources to cache directory ..."
  log_and_run "curl --output ${SRC_CACHE_DIR}/buildroot-${BR_VER}.tar.gz https://buildroot.org/downloads/buildroot-${BR_VER}.tar.gz"
  echo_c 34 "Done.\n"

  # 解压 buildroot 压缩包，到当前目录下（firmware 项目根目录）
  echo_c 34 "Extracting a fresh copy of Buildroot from Buildroot sources ..."
  log_and_run "tar xvf ${SRC_CACHE_DIR}/buildroot-${BR_VER}.tar.gz"
  echo_c 34 "Done.\n"

  echo_c 34 "Copying cached source files back to Buildroot ..."
  # 创建 buildroot-2023.02.7/dl/ 目录
  log_and_run "mkdir -p buildroot-${BR_VER}/dl/"
  # 将  /tmp/buildroot_dl/ 目录下的所有文件（下载的 buildroot 压缩包） 拷贝到 buildroot-2023.02.7/dl/
  log_and_run "cp -rvf ${SRC_CACHE_DIR}/* buildroot-${BR_VER}/dl/"
  echo_c 34 "Done.\n"

  # prevent to double download buildroot
  # make prepare

  echo_c 33 "Start building OpenIPC Firmware ${OPENIPC_VER} for ${SOC}."
  # 记录开始构建的时间到文件 /tmp/openipc_buildtime.txt
  echo "The start-stop times" >/tmp/openipc_buildtime.txt
  date >>/tmp/openipc_buildtime.txt
}

should_fit() {
  local filename=$1
  local maxsize=$2
  local filesize=$(stat --printf="%s" ./output/images/$filename)
  if [[ $filesize -gt $maxsize ]]; then
    export TG_NOTIFY="Warning: $filename is too large: $filesize vs $maxsize"
    echo_c 31 "Warning: $filename is too large: $filesize vs $maxsize"
    exit 1
  fi
}

rename() {
  if grep -q 'BR2_OPENIPC_FLASH_SIZE="16"' ./output/.config; then
    should_fit uImage $MAX_KERNEL_SIZE_ULTIMATE
    should_fit rootfs.squashfs $MAX_ROOTFS_SIZE_ULTIMATE
  else
    should_fit uImage $MAX_KERNEL_SIZE
    should_fit rootfs.squashfs $MAX_ROOTFS_SIZE
  fi
  mv -v ./output/images/uImage ./output/images/uImage.${SOC}
  mv -v ./output/images/rootfs.squashfs ./output/images/rootfs.squashfs.${SOC}
  mv -v ./output/images/rootfs.cpio ./output/images/rootfs.${SOC}.cpio
  mv -v ./output/images/rootfs.tar ./output/images/rootfs.${SOC}.tar
  date >>/tmp/openipc_buildtime.txt
  echo_c 31 "\n\n$(cat /tmp/openipc_buildtime.txt)\n\n"
}

rename_initramfs() {
  should_fit uImage $MAX_KERNEL_SIZE_EXPERIMENTAL
  mv -v ./output/images/uImage ./output/images/uImage.initramfs.${SOC}
  mv -v ./output/images/rootfs.cpio ./output/images/rootfs.${SOC}.cpio
  mv -v ./output/images/rootfs.tar ./output/images/rootfs.${SOC}.tar
  date >>/tmp/openipc_buildtime.txt
  echo_c 31 "\n\n$(cat /tmp/openipc_buildtime.txt)\n\n"
}

autoup_rootfs() {
  echo_c 34 "\nDownloading u-boot created by OpenIPC"
  curl --location --output ./output/images/u-boot-${SOC}-universal.bin \
    https://github.com/OpenIPC/firmware/releases/download/latest/u-boot-${SOC}-universal.bin

  echo_c 34 "\nMaking autoupdate u-boot image"
  ./output/host/bin/mkimage -A arm -O linux -T firmware -n "$OPENIPC_VER" \
    -a 0x0 -e 0x50000 -d ./output/images/u-boot-${SOC}-universal.bin \
    ./output/images/autoupdate-uboot.img

  echo_c 34 "\nMaking autoupdate kernel image"
  ./output/host/bin/mkimage -A arm -O linux -T kernel -C none -n "$OPENIPC_VER" \
    -a 0x50000 -e 0x250000 -d ./output/images/uImage.${SOC} \
    ./output/images/autoupdate-kernel.img

  echo_c 34 "\nMaking autoupdate rootfs image"
  ./output/host/bin/mkimage -A arm -O linux -T filesystem -n "$OPENIPC_VER" \
    -a 0x250000 -e 0x750000 -d ./output/images/rootfs.squashfs.${SOC} \
    ./output/images/autoupdate-rootfs.img
}

# 函数拷贝
copy_function() {
  # 使用 declare -f 命令检查是否存在名为 $1 的函数。
  #   如果函数存在，返回值不为空，那么条件为真，执行后续操作。
  #   如果函数不存在，返回值为空，那么条件为假，使用 || 运算符执行 return 命令，结束函数执行。
  test -n "$(declare -f "$1")" || return

  # 使用 eval 命令，通过替换操作将函数体中所有出现 $1 的地方替换为 $2，然后执行替换后的内容。
  # 具体来说，${_/$1/$2} 是将当前函数体中的 $1 替换为 $2。这样，就复制了原函数并为复制的函数设置了新的名称。
  eval "${_/$1/$2}"
}

uni_build() {
  # 例如 BOARD 为 hi3518ev200_ultimate

  [ -z "$BOARD" ] && BOARD=$FUNCNAME

  # SOC 为 hi3518ev200
  SOC=$(echo $BOARD | cut -sd '_' -f 1)
  # FLAVOR 为 ultimate
  FLAVOR=$(echo $BOARD | cut -sd '_' -f 2)

  set -e

  # 如果 FLAVOR 为 ""，则 使用 lite
  if [ "${FLAVOR}" == "" ]; then
    BOARD="${SOC}_lite"
  fi

  if [ "${SOC}_${FLAVOR}" == "hi3518ev200_lite" ]; then
    NEED_AUTOUP=1
  fi

  echo_c 33 "\n  SoC: $SOC\nBoard: $BOARD\n"

  # 检查变量 COMMAND 是否等于字符串 "all"
  if [ "all" = "${COMMAND}" ]; then
    # 如果相等，则执行 fresh() 函数，参数为 "make BOARD=${BOARD}" 的输出
    # make BOARD=hi3518ev200_ultimate
    fresh $(make BOARD=${BOARD})
  fi

  # 执行 make 命令
  # make BOARD=hi3518ev200_ultimate all
  log_and_run "make BOARD=${BOARD} ${COMMAND}"

  # 判断 COMMAND 是否为 "all"
  if [ "all" == "${COMMAND}" ]; then
    # 判断 BOARD 是否为 "ssc335_initramfs"
    if [ "ssc335_initramfs" == "$BOARD" ]; then
      rename_initramfs
    else
      # 调用 rename() 函数
      rename
    fi

    # -z 检查字符串是否为空，如果字符串为空，则返回 true
    if [ ! -z "$NEED_AUTOUP" ]; then
      autoup_rootfs
    fi
  fi
}

#######

# 检查或则设置锁文件
check_or_set_lock

# 生成可构建的项目列表
build_list_of_projects

# -n 检查字符串是否非空，如果字符串不为空，则返回 true
if [ -n "$1" ]; then
  BOARD=$1
else
  select_project
fi

# -z 检查字符串是否为空，如果字符串为空，则返回 true
[ -z "$BOARD" ] && echo_c 31 "Nothing selected." && drop_lock_and_exit

COMMAND=$2
[ -z "$COMMAND" ] && COMMAND=all

# 遍历数组 FUNCS
for i in "${FUNCS[@]}"; do
  # 调用 copy_function 函数，并传递两个参数给它。第一个参数是字符串 uni_build，第二个参数是数组 FUNCS 的当前元素 $i。
  copy_function uni_build $i
done

echo_c 37 "Building OpenIPC for ${BOARD}"
uni_build $BOARD $COMMAND

drop_lock_and_exit
