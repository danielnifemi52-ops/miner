import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';

function HashrateChart({ workers, stats }) {
  // Generate sample data (in real app, fetch historical stats from API)
  const data = Array.from({ length: 24 }, (_, i) => {
    const hour = new Date();
    hour.setHours(hour.getHours() - (23 - i));
    
    return {
      time: hour.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
      total: Math.random() * 500 + 200,
      ...Object.fromEntries(
        workers.map((w) => [w.name, Math.random() * 200 + 50])
      ),
    };
  });

  const colors = ['#667eea', '#764ba2', '#f093fb', '#4facfe', '#00f2fe'];

  return (
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
        <XAxis dataKey="time" />
        <YAxis label={{ value: 'Hashrate (H/s)', angle: -90, position: 'insideLeft' }} />
        <Tooltip 
          contentStyle={{
            backgroundColor: '#fff',
            border: '1px solid #ddd',
            borderRadius: '4px',
          }}
        />
        <Legend />
        <Line
          type="monotone"
          dataKey="total"
          stroke={colors[0]}
          strokeWidth={2}
          dot={false}
          name="Total Network"
        />
        {workers.slice(0, 4).map((worker, idx) => (
          <Line
            key={worker.id}
            type="monotone"
            dataKey={worker.name}
            stroke={colors[(idx + 1) % colors.length]}
            strokeWidth={1}
            dot={false}
            opacity={0.6}
          />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}

export default HashrateChart;
