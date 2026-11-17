# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# 纯 nftables 环境下 dockerd 的粘合包：
# 通过 fw4 的自动 include 机制（/usr/share/nftables.d/chain-post/forward/）
# 把 Docker 网桥的转发流量放行，不依赖 iptables / xtables。

include $(TOPDIR)/rules.mk

PKG_NAME:=docker-nft
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=OpenWRT-CI-VIKINGYFY

include $(INCLUDE_DIR)/package.mk

define Package/docker-nft
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Firewall
  TITLE:=nftables glue for dockerd (firewall-backend=nftables)
  DEPENDS:=+dockerd
  PKGARCH:=all
endef

define Package/docker-nft/description
  Lets dockerd run with --firewall-backend=nftables on a firewall4 only
  system. Adds fw4 forward rules for docker bridges and docker address
  pools, so containers can be reached and can reach the internet without
  pulling in iptables, xtables or any kmod-ipt-* module.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/docker-nft/install
	$(INSTALL_DIR) $(1)/usr/share/nftables.d/chain-post/forward
	$(INSTALL_DATA) ./files/20-docker.nft $(1)/usr/share/nftables.d/chain-post/forward/20-docker.nft
endef

$(eval $(call BuildPackage,docker-nft))
