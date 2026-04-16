#!/bin/bash
# prepare-runner-node.sh - Prepare K8s worker nodes for Daytona Runner
#
# Run this on each node designated as a daytona-runner node.
# After running, label the node:
#   kubectl label node <NODE_NAME> node-role=daytona-runner
#   kubectl taint node <NODE_NAME> dedicated=daytona-runner:NoSchedule
#
# Requirements:
#   - Ubuntu 22.04+ or RHEL 8+
#   - Root access
#   - XFS-formatted disk for sandbox storage (optional but recommended)

set -euo pipefail

echo "==> Preparing node for Daytona Runner"

# 1. Docker installation (if not present)
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# 2. Configure Docker storage driver with XFS quota support
echo "==> Configuring Docker daemon..."
DOCKER_DATA_DIR="/data/docker"
mkdir -p "${DOCKER_DATA_DIR}"

cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  },
  "live-restore": true,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5
}
EOF

# 3. XFS disk setup (if a dedicated device is specified)
XFS_DEVICE="${1:-}"
if [[ -n "${XFS_DEVICE}" && -b "${XFS_DEVICE}" ]]; then
  echo "==> Setting up XFS on ${XFS_DEVICE}..."
  mkfs.xfs -f "${XFS_DEVICE}"
  mkdir -p "${DOCKER_DATA_DIR}"
  mount -o pquota "${XFS_DEVICE}" "${DOCKER_DATA_DIR}"
  echo "${XFS_DEVICE} ${DOCKER_DATA_DIR} xfs pquota,defaults 0 0" >> /etc/fstab
  echo "==> XFS with pquota enabled on ${DOCKER_DATA_DIR}"
else
  echo "==> Skipping XFS setup (no device specified). Disk quotas will not work."
  echo "==> To enable: $0 /dev/sdX"
fi

# 4. iptables setup
echo "==> Ensuring iptables is available..."
if command -v apt-get &>/dev/null; then
  apt-get install -y iptables
elif command -v yum &>/dev/null; then
  yum install -y iptables-services
fi
mkdir -p /etc/iptables

# 5. System limits
echo "==> Configuring system limits..."
cat > /etc/security/limits.d/99-daytona.conf <<'EOF'
# Daytona Runner limits
*    soft    nofile    1048576
*    hard    nofile    1048576
*    soft    nproc     unlimited
*    hard    nproc     unlimited
root soft    nofile    1048576
root hard    nofile    1048576
EOF

# 6. Kernel parameters
echo "==> Tuning kernel parameters..."
cat > /etc/sysctl.d/99-daytona.conf <<'EOF'
# Network
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1

# File descriptors
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# Memory
vm.overcommit_memory = 1
vm.swappiness = 10

# Bridge networking for Docker
net.bridge.bridge-nf-call-iptables = 1
EOF

modprobe br_netfilter 2>/dev/null || true
modprobe overlay 2>/dev/null || true
sysctl --system

# 7. Restart Docker
echo "==> Restarting Docker..."
systemctl restart docker
systemctl enable docker

# 8. Verification
echo ""
echo "==> Node preparation complete"
echo ""
echo "Docker info:"
docker info | grep -E "Storage Driver|Backing Filesystem"
echo ""
echo "Next steps:"
echo "  1. Label this node:"
echo "     kubectl label node $(hostname) node-role=daytona-runner"
echo "  2. Taint this node (optional, for dedicated runners):"
echo "     kubectl taint node $(hostname) dedicated=daytona-runner:NoSchedule"
echo "  3. Verify XFS (if configured):"
echo "     xfs_info ${DOCKER_DATA_DIR} | grep -i quota"
