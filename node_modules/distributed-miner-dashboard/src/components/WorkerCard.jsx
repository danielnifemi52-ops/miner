import StatusBadge from './StatusBadge';
import './WorkerCard.css';

function WorkerCard({ worker, stats }) {
  const hashrate = stats?.hashrate || 0;
  const cpuPercent = stats?.cpu_percent || 0;
  const uptimeSecs = stats?.uptime_secs || 0;

  const formatUptime = (seconds) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  };

  const isOnline = stats && Object.keys(stats).length > 0;

  return (
    <div className="worker-card">
      <div className="worker-header">
        <div className="worker-info">
          <h3>{worker.name}</h3>
          <span className="platform-badge">{worker.platform}</span>
        </div>
        <StatusBadge online={isOnline} />
      </div>

      <div className="worker-details">
        <div className="detail-item">
          <span className="label">Hashrate</span>
          <span className="value">{hashrate.toFixed(2)} H/s</span>
        </div>
        <div className="detail-item">
          <span className="label">CPU Usage</span>
          <span className="value">{cpuPercent.toFixed(1)}%</span>
        </div>
        <div className="detail-item">
          <span className="label">Uptime</span>
          <span className="value">{formatUptime(uptimeSecs)}</span>
        </div>
      </div>

      <div className="worker-footer">
        <small>
          {worker.ip && `IP: ${worker.ip}`}
          {worker.last_seen && ` • Last: ${new Date(worker.last_seen).toLocaleTimeString()}`}
        </small>
      </div>
    </div>
  );
}

export default WorkerCard;
