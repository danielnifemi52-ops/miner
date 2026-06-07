require("dotenv").config();
const express = require("express");
const cors = require("cors");
const bodyParser = require("body-parser");
const authRoutes = require("./routes/auth");
const workersRoutes = require("./routes/workers");
const configRoutes = require("./routes/config");

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Routes
app.use("/auth", authRoutes);
app.use("/api/config", configRoutes);
// Mount workers router twice:
//   /api/workers — answers GET /api/workers (dashboard)
//   /api         — answers /api/stats, /api/register (agent endpoints)
app.use("/api/workers", workersRoutes);
app.use("/api", workersRoutes);



// Health check (used by UptimeRobot)
app.get("/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// Error handler
app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  res.status(500).json({ error: "Internal server error" });
});

// Start server
app.listen(PORT, () => {
  console.log(`✓ Coordinator running on port ${PORT}`);
  console.log(`  API: http://localhost:${PORT}`);
  console.log(`  Health check: http://localhost:${PORT}/health`);
});
