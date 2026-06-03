#!/bin/bash

# Ensure run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)." >&2
    exit 1
fi

# Logs directory
LOG_DIR="/var/log/xmrig-agent"
mkdir -p "$LOG_DIR"
INSTALL_LOG="$LOG_DIR/install.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$INSTALL_LOG"
}

log "Starting Linux Agent installation..."

COORDINATOR_URL=$1
AGENT_SECRET=$2

# Prompt if not provided
if [ -z "$COORDINATOR_URL" ]; then
    read -p "Enter Coordinator URL (e.g. http://localhost:3000): " COORDINATOR_URL
fi
if [ -z "$AGENT_SECRET" ]; then
    read -s -p "Enter Agent Secret: " AGENT_SECRET
    echo ""
fi

# Clean inputs
COORDINATOR_URL=$(echo "$COORDINATOR_URL" | sed 's/\/$//')
AGENT_SECRET=$(echo "$AGENT_SECRET" | xargs)

log "Coordinator URL: $COORDINATOR_URL"

# Create directories
INSTALL_DIR="/opt/xmrig-agent"
mkdir -p "$INSTALL_DIR"

# Download XMRig
XMRIG_VERSION="v6.21.0"
XMRIG_TAR="xmrig-6.21.0-linux-static-x64.tar.gz"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/$XMRIG_VERSION/$XMRIG_TAR"

log "Downloading XMRig from $XMRIG_URL..."
curl -s -S -L -o "/tmp/$XMRIG_TAR" "$XMRIG_URL"
if [ $? -ne 0 ] || [ ! -f "/tmp/$XMRIG_TAR" ]; then
    log "Error: Failed to download XMRig."
    exit 1
fi

log "Extracting XMRig..."
rm -rf /tmp/xmrig-extract
mkdir -p /tmp/xmrig-extract
tar -xzf "/tmp/$XMRIG_TAR" -C /tmp/xmrig-extract
XMRIG_BIN=$(find /tmp/xmrig-extract -type f -name "xmrig" | head -n 1)

if [ -z "$XMRIG_BIN" ]; then
    log "Error: xmrig binary not found in extracted archive."
    exit 1
fi

cp "$XMRIG_BIN" "$INSTALL_DIR/xmrig"
chmod +x "$INSTALL_DIR/xmrig"
rm -f "/tmp/$XMRIG_TAR"
rm -rf /tmp/xmrig-extract

# Fetch config
log "Fetching mining configuration from coordinator..."
CONFIG_RESP=$(curl -s -S -H "X-Agent-Secret: $AGENT_SECRET" "$COORDINATOR_URL/api/config")
if [ $? -ne 0 ] || [ -z "$CONFIG_RESP" ]; then
    log "Warning: Failed to fetch mining config. Using default fallbacks."
    POOL="pool.moneroocean.stream:10008"
    WALLET="YOUR_WALLET_ADDRESS"
    CPU_MAX=70
else
    if command -v jq >/dev/null 2>&1; then
        POOL=$(echo "$CONFIG_RESP" | jq -r '.pool')
        WALLET=$(echo "$CONFIG_RESP" | jq -r '.wallet')
        CPU_MAX=$(echo "$CONFIG_RESP" | jq -r '.cpu_max_percent')
    elif command -v python3 >/dev/null 2>&1; then
        POOL=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('pool', ''))" <<< "$CONFIG_RESP")
        WALLET=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('wallet', ''))" <<< "$CONFIG_RESP")
        CPU_MAX=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('cpu_max_percent', '70'))" <<< "$CONFIG_RESP")
    fi
fi

# Ensure values are not empty
POOL=${POOL:-"pool.moneroocean.stream:10008"}
WALLET=${WALLET:-"YOUR_WALLET_ADDRESS"}
CPU_MAX=${CPU_MAX:-70}

log "Pool: $POOL"
log "Max CPU: $CPU_MAX%"

# Copy template and create config.json
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cp "$SCRIPT_DIR/config-template.json" "$INSTALL_DIR/config-template.json"
cp "$INSTALL_DIR/config-template.json" "$INSTALL_DIR/config.json"

python3 -c "
import json
with open('$INSTALL_DIR/config.json', 'r') as f:
    config = json.load(f)
config['pools'][0]['url'] = '$POOL'
config['pools'][0]['user'] = '$WALLET'
config['pools'][0]['rig-id'] = '$HOSTNAME'
config['cpu']['max-threads-hint'] = int('$CPU_MAX')
with open('$INSTALL_DIR/config.json', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || {
    sed -i 's/"url": ".*"/"url": "'"$POOL"'"/' "$INSTALL_DIR/config.json"
    sed -i 's/"user": ".*"/"user": "'"$WALLET"'"/' "$INSTALL_DIR/config.json"
    sed -i 's/"rig-id": ".*"/"rig-id": "'"$HOSTNAME"'"/' "$INSTALL_DIR/config.json"
    sed -i 's/"max-threads-hint": [0-9]*/"max-threads-hint": '"$CPU_MAX"'/' "$INSTALL_DIR/config.json"
}

# Get local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')
LOCAL_IP=${LOCAL_IP:-"127.0.0.1"}

# Register worker
log "Registering worker with coordinator..."
REGISTER_RESP=$(curl -s -S -X POST -H "Content-Type: application/json" \
    -H "X-Agent-Secret: $AGENT_SECRET" \
    -d '{"name": "'"$HOSTNAME"'", "platform": "linux", "ip": "'"$LOCAL_IP"'"}' \
    "$COORDINATOR_URL/api/register")

if [ $? -ne 0 ] || [ -z "$REGISTER_RESP" ]; then
    log "Error: Failed to register worker."
    exit 1
fi

if command -v jq >/dev/null 2>&1; then
    WORKER_ID=$(echo "$REGISTER_RESP" | jq -r '.id')
elif command -v python3 >/dev/null 2>&1; then
    WORKER_ID=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('id', ''))" <<< "$REGISTER_RESP")
fi

if [ -z "$WORKER_ID" ] || [ "$WORKER_ID" = "null" ]; then
    log "Error: Registration response did not return a worker ID. Response: $REGISTER_RESP"
    exit 1
fi

log "Worker registered with ID: $WORKER_ID"

# Save agent credentials
mkdir -p /etc/xmrig-agent
cat <<EOF > /etc/xmrig-agent/agent.conf
{
  "coordinator_url": "$COORDINATOR_URL",
  "agent_secret": "$AGENT_SECRET",
  "worker_id": $WORKER_ID
}
EOF
chmod 600 /etc/xmrig-agent/agent.conf
chown root:root /etc/xmrig-agent/agent.conf

# Copy reporter.sh
cp "$SCRIPT_DIR/reporter.sh" "$INSTALL_DIR/reporter.sh"
chmod +x "$INSTALL_DIR/reporter.sh"

# Create dedicated user
if ! id -u xmrig >/dev/null 2>&1; then
    useradd -r -s /bin/false xmrig
fi

chown -R xmrig:xmrig "$INSTALL_DIR"
chown -R xmrig:xmrig "$LOG_DIR"

# Install systemd unit files
cp "$SCRIPT_DIR/xmrig-miner.service" /etc/systemd/system/xmrig-miner.service
cp "$SCRIPT_DIR/xmrig-reporter.service" /etc/systemd/system/xmrig-reporter.service

log "Starting systemd services..."
systemctl daemon-reload
systemctl enable xmrig-miner.service
systemctl enable xmrig-reporter.service
systemctl start xmrig-miner.service
systemctl start xmrig-reporter.service

log "Installation completed successfully."
