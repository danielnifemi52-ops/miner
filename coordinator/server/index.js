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
// Single mount — all worker routes live under /api/* in the router:
//   GET  /api/workers   → router GET  /workers  (dashboard)
//   POST /api/stats     → router POST /stats     (agent)
//   POST /api/register  → router POST /register  (agent)
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

  // Print all registered routes for debugging
  console.log("\n  Registered routes:");
  app._router.stack.forEach((layer) => {
    if (layer.route) {
      const methods = Object.keys(layer.route.methods).join(", ").toUpperCase();
      console.log(`    ${methods.padEnd(6)} ${layer.route.path}`);
    } else if (layer.name === "router" && layer.handle.stack) {
      layer.handle.stack.forEach((r) => {
        if (r.route) {
          const methods = Object.keys(r.route.methods).join(", ").toUpperCase();
          console.log(`    ${methods.padEnd(6)} [router] ${r.route.path}`);
        }
      });
    }
  });
});
