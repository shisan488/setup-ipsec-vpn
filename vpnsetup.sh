#!/bin/sh
#
# Script for automatic setup of an IPsec VPN server on Ubuntu, Debian, CentOS/RHEL,
# Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux 2 and Alpine Linux
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC!
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
# Copyright (C) 2021-2025 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# =====================================================

# Define your own values for these variables
# - IPsec pre-shared key, VPN username and password
# - All values MUST be placed inside 'single quotes'
# - DO NOT use these special characters within values: \ " '

YOUR_IPSEC_PSK=''
YOUR_USERNAME=''
YOUR_PASSWORD=''

# =====================================================

LANGUAGE="en"

# Function to display messages in different languages
display_message() {
  case "$LANGUAGE" in
    "zh")
      case "$1" in
        "error_root") echo "错误：脚本必须以 root 身份运行。尝试 'sudo sh $0'" ;;
        "error_vz") echo "错误：不支持 OpenVZ VPS。" ;;
        "error_lxc") echo "错误：/dev/ppp 缺失。LXC 容器需要配置。" ;;
        "error_os") echo "错误：此脚本仅支持以下操作系统：Ubuntu, Debian, CentOS/RHEL, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux 2 或 Alpine Linux" ;;
        "error_iface") echo "错误：检测到无线接口 '$def_iface'。不要在您的 PC 或 Mac 上运行此脚本！" ;;
        "error_creds") echo "错误：必须指定所有 VPN 凭据。编辑脚本并重新输入它们。" ;;
        "error_dns") echo "错误：指定的 DNS 服务器无效。" ;;
        "error_server_dns") echo "错误：无效的 DNS 名称。'VPN_DNS_NAME' 必须是完全限定的域名 (FQDN)。" ;;
        "error_client_name") echo "错误：无效的客户端名称。仅使用一个单词，不允许使用特殊字符，除了 '-' 和 '_'。" ;;
        "error_apt") echo "错误：无法获取 apt/dpkg 锁。" ;;
        "error_wget") echo "错误：'apt-get install wget' 失败。" ;;
        "error_yum") echo "错误：'yum install wget' 失败。" ;;
        "error_apk") echo "错误：'apk add' 失败。" ;;
        "error_download") echo "错误：无法下载 VPN 设置脚本。" ;;
        "error_tmpdir") echo "错误：无法创建临时目录。" ;;
        *) echo "未知错误。" ;;
      esac
      ;;
    *)
      case "$1" in
        "error_root") echo "Error: Script must be run as root. Try 'sudo sh $0'" ;;
        "error_vz") echo "Error: OpenVZ VPS is not supported." ;;
        "error_lxc") echo "Error: /dev/ppp is missing. LXC containers require configuration." ;;
        "error_os") echo "Error: This script only supports one of the following OS: Ubuntu, Debian, CentOS/RHEL, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux 2 or Alpine Linux" ;;
        "error_iface") echo "Error: Wireless interface '$def_iface' detected. DO NOT run this script on your PC or Mac!" ;;
        "error_creds") echo "Error: All VPN credentials must be specified. Edit the script and re-enter them." ;;
        "error_dns") echo "Error: The DNS server specified is invalid." ;;
        "error_server_dns") echo "Error: Invalid DNS name. 'VPN_DNS_NAME' must be a fully qualified domain name (FQDN)." ;;
        "error_client_name") echo "Error: Invalid client name. Use one word only, no special characters except '-' and '_'." ;;
        "error_apt") echo "Error: Could not get apt/dpkg lock." ;;
        "error_wget") echo "Error: 'apt-get install wget' failed." ;;
        "error_yum") echo "Error: 'yum install wget' failed." ;;
        "error_apk") echo "Error: 'apk add' failed." ;;
        "error_download") echo "Error: Could not download VPN setup script." ;;
        "error_tmpdir") echo "Error: Could not create temporary directory." ;;
        *) echo "Unknown error." ;;
      esac
      ;;
  esac
}

exiterr() { display_message "$1"; exit 1; }

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

check_dns_name() {
  FQDN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$FQDN_REGEX"
}

check_root() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "error_root"
  fi
}

check_vz() {
  if [ -f /proc/user_beancounters ]; then
    exiterr "error_vz"
  fi
}

check_lxc() {
  # shellcheck disable=SC2154
  if [ "$container" = "lxc" ] && [ ! -e /dev/ppp ]; then
    exiterr "error_lxc"
  fi
}

check_os() {
  rh_file="/etc/redhat-release"
  if [ -f "$rh_file" ]; then
    os_type=centos
    if grep -q "Red Hat" "$rh_file"; then
      os_type=rhel
    fi
    [ -f /etc/oracle-release ] && os_type=ol
    grep -qi rocky "$rh_file" && os_type=rocky
    grep -qi alma "$rh_file" && os_type=alma
    if grep -q "release 7" "$rh_file"; then
      os_ver=7
    elif grep -q "release 8" "$rh_file"; then
      os_ver=8
      grep -qi stream "$rh_file" && os_ver=8s
    elif grep -q "release 9" "$rh_file"; then
      os_ver=9
      grep -qi stream "$rh_file" && os_ver=9s
    else
      exiterr "This script only supports CentOS/RHEL 7-9."
    fi
    if [ "$os_type" = "centos" ] \
      && { [ "$os_ver" = 7 ] || [ "$os_ver" = 8 ] || [ "$os_ver" = 8s ]; }; then
      exiterr "error_os"
    fi
  elif grep -qs "Amazon Linux release 2 " /etc/system-release; then
    os_type=amzn
    os_ver=2
  elif grep -qs "Amazon Linux release 2023" /etc/system-release; then
    exiterr "Amazon Linux 2023 is not supported."
  else
    os_type=$(lsb_release -si 2>/dev/null)
    [ -z "$os_type" ] && [ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")
    case $os_type in
      [Uu]buntu)
        os_type=ubuntu
        ;;
      [Dd]ebian|[Kk]ali)
        os_type=debian
        ;;
      [Rr]aspbian)
        os_type=raspbian
        ;;
      [Aa]lpine)
        os_type=alpine
        ;;
      *)
        exiterr "error_os"
        ;;
    esac
    if [ "$os_type" = "alpine" ]; then
      os_ver=$(. /etc/os-release && printf '%s' "$VERSION_ID" | cut -d '.' -f 1,2)
      if [ "$os_ver" != "3.20" ] && [ "$os_ver" != "3.21" ]; then
        exiterr "This script only supports Alpine Linux 3.20/3.21."
      fi
    else
      os_ver=$(sed 's/\..*//' /etc/debian_version | tr -dc 'A-Za-z0-9')
      if [ "$os_ver" = 8 ] || [ "$os_ver" = 9 ] || [ "$os_ver" = "stretchsid" ] \
        || [ "$os_ver" = "bustersid" ]; then
cat 1>&2 <<EOF
Error: This script requires Debian >= 10 or Ubuntu >= 20.04.
       This version of Ubuntu/Debian is too old and not supported.
EOF
        exit 1
      fi
      if [ "$os_ver" = "trixiesid" ] && [ -f /etc/os-release ] \
        && [ "$(. /etc/os-release && printf '%s' "$VERSION_ID")" = "24.10" ]; then
cat 1>&2 <<EOF
Error: This script does not support Ubuntu 24.10.
       You may use e.g. Ubuntu 24.04 LTS instead.
EOF
        exit 1
      fi
    fi
  fi
}

check_iface() {
  def_iface=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
  if [ "$os_type" != "alpine" ]; then
    [ -z "$def_iface" ] && def_iface=$(ip -4 route list 0/0 2>/dev/null | grep -m 1 -Po '(?<=dev )(\S+)')
  fi
  def_state=$(cat "/sys/class/net/$def_iface/operstate" 2>/dev/null)
  check_wl=0
  if [ -n "$def_state" ] && [ "$def_state" != "down" ]; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      if ! uname -m | grep -qi -e '^arm' -e '^aarch64'; then
        check_wl=1
      fi
    else
      check_wl=1
    fi
  fi
  if [ "$check_wl" = 1 ]; then
    case $def_iface in
      wl*)
        exiterr "error_iface"
        ;;
    esac
  fi
}

check_creds() {
  [ -n "$YOUR_IPSEC_PSK" ] && VPN_IPSEC_PSK="$YOUR_IPSEC_PSK"
  [ -n "$YOUR_USERNAME" ] && VPN_USER="$YOUR_USERNAME"
  [ -n "$YOUR_PASSWORD" ] && VPN_PASSWORD="$YOUR_PASSWORD"
  if [ -z "$VPN_IPSEC_PSK" ] && [ -z "$VPN_USER" ] && [ -z "$VPN_PASSWORD" ]; then
    return 0
  fi
  if [ -z "$VPN_IPSEC_PSK" ] || [ -z "$VPN_USER" ] || [ -z "$VPN_PASSWORD" ]; then
    exiterr "error_creds"
  fi
  if printf '%s' "$VPN_IPSEC_PSK $VPN_USER $VPN_PASSWORD" | LC_ALL=C grep -q '[^ -~]\+'; then
    exiterr "VPN credentials must not contain non-ASCII characters."
  fi
  case "$VPN_IPSEC_PSK $VPN_USER $VPN_PASSWORD" in
    *[\\\"\']*)
      exiterr "VPN credentials must not contain these special characters: \\ \" '"
      ;;
  esac
}

check_dns() {
  if { [ -n "$VPN_DNS_SRV1" ] && ! check_ip "$VPN_DNS_SRV1"; } \
    || { [ -n "$VPN_DNS_SRV2" ] && ! check_ip "$VPN_DNS_SRV2"; }; then
    exiterr "error_dns"
  fi
}

check_server_dns() {
  if [ -n "$VPN_DNS_NAME" ] && ! check_dns_name "$VPN_DNS_NAME"; then
    exiterr "error_server_dns"
  fi
}

check_client_name() {
  if [ -n "$VPN_CLIENT_NAME" ]; then
    name_len="$(printf '%s' "$VPN_CLIENT_NAME" | wc -m)"
    if [ "$name_len" -gt "64" ] || printf '%s' "$VPN_CLIENT_NAME" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+' \
      || case $VPN_CLIENT_NAME in -*) true ;; *) false ;; esac; then
      exiterr "error_client_name"
    fi
  fi
}

wait_for_apt() {
  count=0
  apt_lk=/var/lib/apt/lists/lock
  pkg_lk=/var/lib/dpkg/lock
  while fuser "$apt_lk" "$pkg_lk" >/dev/null 2>&1 \
    || lsof "$apt_lk" >/dev/null 2>&1 || lsof "$pkg_lk" >/dev/null 2>&1; do
    [ "$count" = 0 ] && echo "## Waiting for apt to be available..."
    [ "$count" -ge 100 ] && exiterr "error_apt"
    count=$((count+1))
    printf '%s' '.'
    sleep 3
  done
}

install_pkgs() {
  if ! command -v wget >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      wait_for_apt
      export DEBIAN_FRONTEND=noninteractive
      (
        set -x
        apt-get -yqq update || apt-get -yqq update
      ) || exiterr "error_apt"
      (
        set -x
        apt-get -yqq install wget >/dev/null || apt-get -yqq install wget >/dev/null
      ) || exiterr "error_wget"
    elif [ "$os_type" != "alpine" ]; then
      (
        set -x
        yum -y -q install wget >/dev/null || yum -y -q install wget >/dev/null
      ) || exiterr "error_yum"
    fi
  fi
  if [ "$os_type" = "alpine" ]; then
    (
      set -x
      apk add -U -q bash coreutils grep net-tools sed wget
    ) || exiterr "error_apk"
  fi
}

get_setup_url() {
  base_url1="https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/master"
  base_url2="https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master"
  sh_file="vpnsetup_ubuntu.sh"
  if [ "$os_type" = "centos" ] || [ "$os_type" = "rhel" ] || [ "$os_type" = "rocky" ] \
    || [ "$os_type" = "alma" ] || [ "$os_type" = "ol" ]; then
    sh_file="vpnsetup_centos.sh"
  elif [ "$os_type" = "amzn" ]; then
    sh_file="vpnsetup_amzn.sh"
  elif [ "$os_type" = "alpine" ]; then
    sh_file="vpnsetup_alpine.sh"
  fi
  setup_url1="$base_url1/$sh_file"
  setup_url2="$base_url2/$sh_file"
}

run_setup() {
  status=0
  if tmpdir=$(mktemp --tmpdir -d vpn.XXXXX 2>/dev/null); then
    if ( set -x; wget -t 3 -T 30 -q -O "$tmpdir/vpn.sh" "$setup_url1" \
      || wget -t 3 -T 30 -q -O "$tmpdir/vpn.sh" "$setup_url2" \
      || curl -m 30 -fsL "$setup_url1" -o "$tmpdir/vpn.sh" 2>/dev/null ); then
      VPN_IPSEC_PSK="$VPN_IPSEC_PSK" VPN_USER="$VPN_USER" \
      VPN_PASSWORD="$VPN_PASSWORD" \
      VPN_PUBLIC_IP="$VPN_PUBLIC_IP" VPN_L2TP_NET="$VPN_L2TP_NET" \
      VPN_L2TP_LOCAL="$VPN_L2TP_LOCAL" VPN_L2TP_POOL="$VPN_L2TP_POOL" \
      VPN_XAUTH_NET="$VPN_XAUTH_NET" VPN_XAUTH_POOL="$VPN_XAUTH_POOL" \
      VPN_DNS_SRV1="$VPN_DNS_SRV1" VPN_DNS_SRV2="$VPN_DNS_SRV2" \
      VPN_DNS_NAME="$VPN_DNS_NAME" VPN_CLIENT_NAME="$VPN_CLIENT_NAME" \
      VPN_PROTECT_CONFIG="$VPN_PROTECT_CONFIG" \
      VPN_CLIENT_VALIDITY="$VPN_CLIENT_VALIDITY" \
      VPN_SKIP_IKEV2="$VPN_SKIP_IKEV2" VPN_SWAN_VER="$VPN_SWAN_VER" \
      /bin/bash "$tmpdir/vpn.sh" || status=1
    else
      status=1
      display_message "error_download" >&2
    fi
    /bin/rm -f "$tmpdir/vpn.sh"
    /bin/rmdir "$tmpdir"
  else
    exiterr "error_tmpdir"
  fi
}

vpnsetup() {
  check_root
  check_vz
  check_lxc
  check_os
  check_iface
  check_creds
  check_dns
  check_server_dns
  check_client_name
  install_pkgs
  get_setup_url
  run_setup
}

## Defer setup until we have the complete script
vpnsetup "$@"

# Run shunit2 tests
./shunit2/shunit2 tests/hello_world_test.sh

exit "$status"
