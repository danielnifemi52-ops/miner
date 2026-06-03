import './StatusBadge.css';

function StatusBadge({ online }) {
  return (
    <div className={`status-badge ${online ? 'online' : 'offline'}`}>
      <span className="dot"></span>
      {online ? 'Online' : 'Offline'}
    </div>
  );
}

export default StatusBadge;
