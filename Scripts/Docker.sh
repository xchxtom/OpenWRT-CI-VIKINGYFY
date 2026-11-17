#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 在 firewall4（纯 nftables）固件里启用 Docker：
#   1. 去掉 dockerd 对 iptables / xtables / kmod-ipt-* 的硬依赖
#   2. 打补丁让 dockerd 的 procd 脚本生成 "firewall-backend": "nftables"
#   3. 安装本地包 docker-nft，用 fw4 的 nftables.d 钩子放行容器转发
#
# 环境变量 WRT_DOCKER：
#   all  （默认）全部平台
#   auto 仅 X86 / ROCKCHIP 等带大容量存储的平台
#   none 不启用
#
# 依赖 dockerd >= 29.0.0（nftables 防火墙后端自 29.0 引入，
# immortalwrt/packages 当前为 29.x；24.10 分支上的 27.x 无此后端）

DOCKER_PKG_DIR="./feeds/packages/utils/dockerd"
DOCKERD_MAKE="$DOCKER_PKG_DIR/Makefile"
DOCKERD_INIT="$DOCKER_PKG_DIR/files/dockerd.init"
NFT_SRC="$GITHUB_WORKSPACE/Scripts/docker-nft"
NFT_DST="./package/docker-nft"

info() { echo -e "\n[docker] $*"; }
warn() { echo "[docker] 警告：$*"; }

DOCKER_MODE=${WRT_DOCKER:-all}

case "${DOCKER_MODE,,}" in
none | no | off)
	info "WRT_DOCKER=$DOCKER_MODE，跳过 Docker"
	exit 0
	;;
auto)
	if [[ "${WRT_CONFIG^^}" == X86* || "${WRT_CONFIG^^}" == ROCKCHIP* ]]; then
		DOCKER_ON=1
	else
		DOCKER_ON=0
	fi
	;;
*)
	DOCKER_ON=1
	;;
esac

if [ "$DOCKER_ON" != "1" ]; then
	info "WRT_DOCKER=$DOCKER_MODE 且平台为 $WRT_CONFIG，跳过 Docker"
	exit 0
fi

# ---------------------------------------------------------------------------
# 1. 去掉 dockerd 的 iptables 依赖
# ---------------------------------------------------------------------------
if [ -f "$DOCKERD_MAKE" ]; then
	info "移除 dockerd 的 iptables / xtables 依赖"

	# iptables、ip6tables、iptables-mod-*、kmod-ipt-*、kmod-nf-ipvs 全部删掉
	sed -i -E '/^[[:space:]]*\+(IPV6:)?(iptables|ip6tables|kmod-ipt-|kmod-nf-ipvs)/d' "$DOCKERD_MAKE"

	if sed -n '/^define Package\/dockerd$/,/^endef/p' "$DOCKERD_MAKE" | grep -qE '\+.*(iptables|kmod-ipt)'; then
		warn "dockerd/Makefile 里仍有 iptables 依赖，上游写法可能变了，请人工确认"
	else
		echo "[docker] dockerd/Makefile 已无 iptables 依赖"
	fi
else
	warn "未找到 $DOCKERD_MAKE，跳过依赖修补"
fi

# ---------------------------------------------------------------------------
# 2. 让 dockerd 启动脚本默认使用 nftables 防火墙后端
# ---------------------------------------------------------------------------
if [ -f "$DOCKERD_INIT" ]; then
	info "为 dockerd 启动脚本加入 firewall-backend 选项"

	if grep -q 'firewall_backend' "$DOCKERD_INIT"; then
		echo "[docker] 启动脚本已打过补丁，跳过"
	else
		# 读取 uci 选项，默认 nftables
		sed -i 's#^\(\s*config_get_bool ip6tables globals ip6tables "0"\)$#\1\n\tconfig_get firewall_backend globals firewall_backend "nftables"#' "$DOCKERD_INIT"
		# 写进 daemon.json
		sed -i 's#^\(\s*json_add_boolean "ip6tables" "[^"]*"\)$#\1\n\t[ -z "${firewall_backend}" ] || json_add_string "firewall-backend" "${firewall_backend}"#' "$DOCKERD_INIT"
		# nftables 后端没有 DOCKER-USER 链，也不要再去调用 iptables 命令
		sed -i 's#^\(\s*\)\[ "${iptables}" -eq "1" \] && config_foreach iptables_add_blocking_rule firewall#\1[ "${iptables}" -eq "1" ] \&\& [ "${firewall_backend}" != "nftables" ] \&\& config_foreach iptables_add_blocking_rule firewall#' "$DOCKERD_INIT"

		if grep -q '"firewall-backend"' "$DOCKERD_INIT"; then
			echo "[docker] 启动脚本补丁完成"
		else
			warn "启动脚本补丁未完全生效，请人工确认 $DOCKERD_INIT"
		fi
	fi
else
	warn "未找到 $DOCKERD_INIT，跳过启动脚本补丁"
fi

# ---------------------------------------------------------------------------
# 3. 安装本地包 docker-nft（fw4 放行规则）
# ---------------------------------------------------------------------------
if [ -d "$NFT_SRC" ]; then
	info "安装本地包 docker-nft"
	mkdir -p ./package
	rm -rf "$NFT_DST"
	cp -rf "$NFT_SRC" "$NFT_DST"
	echo "[docker] docker-nft 已放入 $NFT_DST"
else
	warn "未找到 $NFT_SRC，容器转发可能被 fw4 拦截"
fi

# ---------------------------------------------------------------------------
# 4. 追加编译配置
# ---------------------------------------------------------------------------
info "写入 Docker 编译配置"

cat >>./.config <<'EOF'

#Docker（nftables 后端，零 iptables 依赖）
CONFIG_PACKAGE_docker-nft=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_docker=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_DOCKER_CGROUP_OPTIONS=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-dummy=y
CONFIG_PACKAGE_kmod-macvlan=y
CONFIG_PACKAGE_kmod-nft-core=y
CONFIG_PACKAGE_kmod-nft-nat=y
CONFIG_PACKAGE_kmod-nf-nat=y
CONFIG_PACKAGE_kmod-nf-conntrack=y
EOF

echo "[docker] Docker 配置已追加（WRT_DOCKER=$DOCKER_MODE）"
