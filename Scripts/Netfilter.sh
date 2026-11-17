#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 修复 kmod 文件归属冲突：nf_conntrack_bridge.ko 被两个包同时声明
#
#   include/netfilter.mk 把 nf_conntrack_bridge.ko 归到 NFT_BRIDGE 模块组
#   （$(call nf_add,NFT_BRIDGE,CONFIG_NF_CONNTRACK_BRIDGE, $(P_EBT)nf_conntrack_bridge)），
#   于是 kmod-nft-bridge 的 FILES 会包含它；
#   而 package/kernel/linux/modules/netfilter.mk 里又单独定义了
#   KernelPackage/nf-conntrack-bridge，FILES 也声明同一个 .ko。
#
#   firewall4 同时依赖 +kmod-nft-bridge 与 +kmod-nf-conntrack-bridge，
#   两个 ipk 都装到 root 时 opkg 报：
#     check_data_file_clashes: Package kmod-nft-bridge wants to install file
#       .../nf_conntrack_bridge.ko
#     But that file is already provided by package * kmod-nf-conntrack-bridge
#     opkg_install_cmd: Cannot install package kmod-nft-bridge.
#   后续依赖 uci-firewall -> firewall4 的包（dockerd / docker-nft 等）一并失败，
#   镜像构建在 package/install 阶段以 Error 255 中断。
#
# 处理：把该 .ko 的文件归属收归 kmod-nf-conntrack-bridge 一家，
#       同时保留 KCONFIG_NFT_BRIDGE 里的 CONFIG_NF_CONNTRACK_BRIDGE 符号，
#       保证 kmod-nft-bridge 的 KCONFIG 与 AUTOLOAD 语义不变。

NF_INC="./include/netfilter.mk"
NF_MOD="./package/kernel/linux/modules/netfilter.mk"

info() { echo -e "\n[netfilter] $*"; }
warn() { echo "[netfilter] 警告：$*"; }

if [ ! -f "$NF_INC" ] || [ ! -f "$NF_MOD" ]; then
	warn "未找到 netfilter.mk，跳过"
	exit 0
fi

# 只有当 nf-conntrack-bridge 是独立的 kmod 包时才需要去重
if ! grep -q "define KernelPackage/nf-conntrack-bridge" "$NF_MOD"; then
	info "源码没有独立的 kmod-nf-conntrack-bridge，无需去重"
	exit 0
fi

DUP='nf_add,NFT_BRIDGE,CONFIG_NF_CONNTRACK_BRIDGE, $(P_EBT)nf_conntrack_bridge'
FIXED='nf_add,NFT_BRIDGE,CONFIG_NF_CONNTRACK_BRIDGE,'

if grep -qF "$DUP" "$NF_INC"; then
	info "nf_conntrack_bridge.ko 归属去重（改为仅 kmod-nf-conntrack-bridge 提供）"
	sed -i "s#$DUP#$FIXED#" "$NF_INC"

	if grep -qF "$DUP" "$NF_INC"; then
		warn "去重失败，请人工检查 $NF_INC"
		exit 1
	fi
elif grep -n "nf_add,NFT_BRIDGE" "$NF_INC" | grep -qF 'nf_conntrack_bridge'; then
	# 上游改写了这一行，补丁定位失败；此时构建必将在 package/install 阶段失败，直接中断
	warn "nf_add 写法已变化，无法自动去重，请人工检查 $NF_INC"
	grep -n "nf_add,NFT_BRIDGE" "$NF_INC" || true
	exit 1
else
	info "源码已去重或已无该归属声明，跳过"
fi

# 校验：kmod-nft-bridge 的 FILES 不再通过 NFT_BRIDGE 组携带该 .ko
if grep -n "nf_add,NFT_BRIDGE,CONFIG_NF_CONNTRACK_BRIDGE" "$NF_INC" | grep -qF 'nf_conntrack_bridge'; then
	warn "kmod-nft-bridge 仍声明 nf_conntrack_bridge.ko"
else
	echo "[netfilter] nf_conntrack_bridge.ko 已单一归属：ok"
fi

echo "[netfilter] 完成"
