#!/bin/bash
# Description: Post-CIS Hardening configuration for MicroK8s (Toggle Enable/Disable)
# Usage: ./microk8s-cis-patch.sh [enable|disable]

set -euo pipefail

# ==========================================
# Variables
# ==========================================
SYSCTL_CONF="/etc/sysctl.d/99-microk8s-custom.conf"
MODULES_CONF="/etc/modules-load.d/microk8s-br_netfilter.conf"
INTERFACES=("cni0" "flannel.1" "vxlan.calico" "cali+")
PORTS=("16443/tcp" "10250/tcp" "10255/tcp" "25000/tcp" "19001/tcp")

# ==========================================
# Logging Functions
# ==========================================
log_info() {
    local msg="$1"
    echo -e "[\033[32mINFO\033[0m] $msg"
    logger -t microk8s-cis-patch -p user.info "$msg"
}

log_error() {
    local msg="$1"
    echo -e "[\033[31mERROR\033[0m] $msg" >&2
    logger -t microk8s-cis-patch -p user.err "$msg"
}

# ==========================================
# Pre-checks
# ==========================================
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root. Please use sudo." 
   exit 1
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 {enable|disable}"
    exit 1
fi

COMMAND="$1"

# ==========================================
# Enable Function
# ==========================================
enable_patch() {
    log_info "ENABLING MicroK8s network patching..."

    # 1. Sysctl & Modules
    log_info "Configuring sysctl parameters..."
    cat <<EOF > "$SYSCTL_CONF"
# MicroK8s Overrides for CIS Hardening
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    if ! lsmod | grep -q br_netfilter; then
        log_info "Loading br_netfilter module..."
        modprobe br_netfilter || true
        echo "br_netfilter" > "$MODULES_CONF"
    fi

    sysctl --system >/dev/null

    # 2. UFW Rules
    log_info "Configuring UFW rules..."
    for IFACE in "${INTERFACES[@]}"; do
        ufw allow in on "$IFACE" >/dev/null
        ufw allow out on "$IFACE" >/dev/null
    done
    log_info "Allowed UFW traffic on CNI interfaces."

    ufw default allow routed >/dev/null
    log_info "Set UFW default routed policy to ALLOW."

    for PORT in "${PORTS[@]}"; do
        ufw allow "$PORT" >/dev/null
    done
    log_info "Allowed UFW internal cluster ports."

    ufw reload >/dev/null
    log_info "UFW reloaded successfully. Enable completed!"
}

# ==========================================
# Disable Function
# ==========================================
disable_patch() {
    log_info "DISABLING MicroK8s network patching (Reverting to CIS strict mode)..."

    # 1. Revert Sysctl & Modules
    log_info "Removing sysctl overrides..."
    rm -f "$SYSCTL_CONF"
    rm -f "$MODULES_CONF"

    # Force runtime values back to CIS defaults (0)
    # Note: || true is used in case br_netfilter is missing, preventing script crash
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
    sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
    sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true

    # 2. Revert UFW Rules
    log_info "Removing UFW rules..."
    for IFACE in "${INTERFACES[@]}"; do
        ufw delete allow in on "$IFACE" >/dev/null 2>&1 || true
        ufw delete allow out on "$IFACE" >/dev/null 2>&1 || true
    done
    log_info "Removed UFW traffic rules for CNI interfaces."

    # CIS Default is usually drop or deny for routed traffic
    ufw default drop routed >/dev/null
    log_info "Reverted UFW default routed policy to DROP."

    for PORT in "${PORTS[@]}"; do
        ufw delete allow "$PORT" >/dev/null 2>&1 || true
    done
    log_info "Removed UFW internal cluster ports."

    ufw reload >/dev/null
    log_info "UFW reloaded successfully. Disable completed!"
}

# ==========================================
# Main Execution
# ==========================================
case "$COMMAND" in
    enable)
        enable_patch
        ;;
    disable)
        disable_patch
        ;;
    *)
        echo "Invalid argument: $COMMAND"
        echo "Usage: $0 {enable|disable}"
        exit 1
        ;;
esac
