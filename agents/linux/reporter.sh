#!/bin/bash

# Configuration files
CONF_FILE="/etc/xmrig-agent/agent.conf"
XMRIG_CONF="/opt/xmrig-agent/config.json"
TEMPLATE_CONF="/opt/xmrig-agent/config-template.json"
LOG_FILE="/var/log/xmrig-agent/reporter.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting XMRig Stats Reporter..."

if [ ! -f "$CONF_FILE" ]; then
    log "Error: agent.conf not found at $CONF_FILE. Exiting."
    exit 1
fi

# Load config using python3 since it's standard and jq might not be present
parse_json_val() {
    python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('$1', ''))" 2>/dev/null
}

CONF_CONTENT=$(cat "$CONF_FILE")
COORDINATOR_URL=$(echo "$CONF_CONTENT" | parse_json_val "coordinator_url")
AGENT_SECRET=$(echo "$CONF_CONTENT" | parse_json_val "agent_secret")
WORKER_ID=$(echo "$CONF_CONTENT" | parse_json_val "worker_id")

if [ -z "$COORDINATOR_URL" ] || [ -z "$AGENT_SECRET" ] || [ -z "$WORKER_ID" ]; then
    log "Error: Invalid config in $CONF_FILE. Exiting."
    exit 1
fi

log "Coordinator: $COORDINATOR_URL"
log "Worker ID: $WORKER_ID"

START_TIME=$(date +%s)
LOOP_COUNT=0

while true; do
    # Wrap loop body in try/catch equivalent (if error occurs, don't exit)
    {
        # Get stats from XMRig HTTP API
        HASHRATE=0.0
        MINER_UPTIME=0
        
        XMRIG_STATS=$(curl -s --max-time 5 "http://localhost:3333/1/summary")
        if [ ! -z "$XMRIG_STATS" ]; then
            if command -v jq >/dev/null 2>&1; then
                HASHRATE=$(echo "$XMRIG_STATS" | jq -r '.hashrate.total[0] // 0.0')
                MINER_UPTIME=$(echo "$XMRIG_STATS" | jq -r '.connection.uptime // 0')
            elif command -v python3 >/dev/null 2>&1; then
                HASHRATE=$(python3 -c "import sys, json; data=json.loads(sys.stdin.read()); print(data.get('hashrate', {}).get('total', [0.0])[0] or 0.0)" <<< "$XMRIG_STATS")
                MINER_UPTIME=$(python3 -c "import sys, json; data=json.loads(sys.stdin.read()); print(data.get('connection', {}).get('uptime', 0) or 0)" <<< "$XMRIG_STATS")
            fi
        else
            log "Warning: Failed to connect to XMRig HTTP API."
        fi

        # Get system CPU load percentage
        if command -v top >/dev/null 2>&1; then
            # CPU_IDLE is column 8 in standard top output
            CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}')
            if [ -z "$CPU_IDLE" ]; then
                CPU_IDLE=$(top -bn1 | grep -i "cpu" | head -n 1 | awk -F',' '{print $4}' | awk '{print $1}')
            fi
            # In some locales, float has comma (e.g. 98,4). Replace comma with dot.
            CPU_IDLE=${CPU_IDLE//,/\.}
            CPU_PERCENT=$(echo "$CPU_IDLE" | awk '{print 100 - $1}')
        else
            CPU_PERCENT=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
        fi
        
        # Ensure CPU_PERCENT is float/number
        if [[ ! "$CPU_PERCENT" =~ ^[0-9.]+$ ]]; then
            CPU_PERCENT=0.0
        fi

        # Calculate uptime
        CURRENT_TIME=$(date +%s)
        UPTIME_SECS=$((CURRENT_TIME - START_TIME))

        # Send stats to coordinator
        STATS_PAYLOAD=$(cat <<EOF
{
  "worker_id": $WORKER_ID,
  "hashrate": $HASHRATE,
  "cpu_percent": $CPU_PERCENT,
  "uptime_secs": $UPTIME_SECS
}
EOF
)
        STATS_RESP=$(curl -s -X POST -H "Content-Type: application/json" \
            -H "X-Agent-Secret: $AGENT_SECRET" \
            -d "$STATS_PAYLOAD" \
            --max-time 10 \
            "$COORDINATOR_URL/api/stats")

        # Periodically log success
        if [ $((LOOP_COUNT % 5)) -eq 0 ]; then
            log "Stats reported: Hashrate=$HASHRATE H/s, CPU=$CPU_PERCENT%, Uptime=$UPTIME_SECS s. Response: $STATS_RESP"
        fi

        # Sync config every 5 loops
        if [ $((LOOP_COUNT % 5)) -eq 0 ] && [ $LOOP_COUNT -gt 0 ]; then
            CONFIG_RESP=$(curl -s -H "X-Agent-Secret: $AGENT_SECRET" --max-time 10 "$COORDINATOR_URL/api/config")
            if [ ! -z "$CONFIG_RESP" ] && [[ "$CONFIG_RESP" == *"pool"* ]]; then
                # Load config values
                if command -v jq >/dev/null 2>&1; then
                    REMOTE_POOL=$(echo "$CONFIG_RESP" | jq -r '.pool')
                    REMOTE_WALLET=$(echo "$CONFIG_RESP" | jq -r '.wallet')
                    REMOTE_CPU_MAX=$(echo "$CONFIG_RESP" | jq -r '.cpu_max_percent')
                elif command -v python3 >/dev/null 2>&1; then
                    REMOTE_POOL=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('pool', ''))" <<< "$CONFIG_RESP")
                    REMOTE_WALLET=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('wallet', ''))" <<< "$CONFIG_RESP")
                    REMOTE_CPU_MAX=$(python3 -c "import sys, json; print(json.loads(sys.stdin.read()).get('cpu_max_percent', '70'))" <<< "$CONFIG_RESP")
                fi

                # Check if file exists and parse local values
                if [ -f "$XMRIG_CONF" ]; then
                    if command -v jq >/dev/null 2>&1; then
                        LOCAL_POOL=$(jq -r '.pools[0].url' "$XMRIG_CONF")
                        LOCAL_WALLET=$(jq -r '.pools[0].user' "$XMRIG_CONF")
                        LOCAL_CPU_MAX=$(jq -r '.cpu."max-threads-hint"' "$XMRIG_CONF")
                    elif command -v python3 >/dev/null 2>&1; then
                        LOCAL_POOL=$(python3 -c "import json; print(json.load(open('$XMRIG_CONF')).get('pools', [{}])[0].get('url', ''))")
                        LOCAL_WALLET=$(python3 -c "import json; print(json.load(open('$XMRIG_CONF')).get('pools', [{}])[0].get('user', ''))")
                        LOCAL_CPU_MAX=$(python3 -c "import json; print(json.load(open('$XMRIG_CONF')).get('cpu', {}).get('max-threads-hint', ''))")
                    fi

                    CHANGED=false
                    if [ "$REMOTE_POOL" != "$LOCAL_POOL" ]; then CHANGED=true; fi
                    if [ "$REMOTE_WALLET" != "$LOCAL_WALLET" ]; then CHANGED=true; fi
                    if [ "$REMOTE_CPU_MAX" != "$LOCAL_CPU_MAX" ]; then CHANGED=true; fi

                    if [ "$CHANGED" = true ]; then
                        log "Configuration change detected. Rebuilding config.json..."
                        
                        # Use template or local config if template missing
                        USE_TEMPLATE="$TEMPLATE_CONF"
                        if [ ! -f "$TEMPLATE_CONF" ]; then
                            USE_TEMPLATE="$XMRIG_CONF"
                        fi

                        python3 -c "
import json
with open('$USE_TEMPLATE', 'r') as f:
    config = json.load(f)
config['pools'][0]['url'] = '$REMOTE_POOL'
config['pools'][0]['user'] = '$REMOTE_WALLET'
config['cpu']['max-threads-hint'] = int('$REMOTE_CPU_MAX')
with open('$XMRIG_CONF', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || {
                            # sed fallback
                            sed -i 's/"url": ".*"/"url": "'"$REMOTE_POOL"'"/' "$XMRIG_CONF"
                            sed -i 's/"user": ".*"/"user": "'"$REMOTE_WALLET"'"/' "$XMRIG_CONF"
                            sed -i 's/"max-threads-hint": [0-9]*/"max-threads-hint": '"$REMOTE_CPU_MAX"'/' "$XMRIG_CONF"
                        }

                        log "Restarting xmrig-miner service..."
                        systemctl restart xmrig-miner
                    fi
                fi
            fi
        fi

    } 2>/dev/null || log "Warning: Error encountered in stats reporter loop."

    LOOP_COUNT=$((LOOP_COUNT + 1))
    sleep 60
done
