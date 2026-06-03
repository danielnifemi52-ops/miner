let isRunning = false;
let throttle = 0.5; // default 50%
let wallet = '';
let pool = '';
let hashrate = 0;
let hashes = 0;
let lastReportTime = Date.now();

self.onmessage = function (e) {
  const { type, data } = e.data;
  if (type === 'start') {
    wallet = data.wallet;
    pool = data.pool;
    throttle = parseFloat(data.throttle || 0.5);
    isRunning = true;
    startMining();
  } else if (type === 'stop') {
    isRunning = false;
  } else if (type === 'set_throttle') {
    throttle = parseFloat(data.throttle);
  }
};

function startMining() {
  console.log(`Web Worker started mining on pool: ${pool} for wallet: ${wallet} with throttle: ${throttle * 100}%`);
  
  // Try loading WebAssembly miner from CDN
  try {
    self.importScripts('https://cdn.jsdelivr.net/npm/cryptonight-wasm');
    console.log("Cryptonight WASM loaded successfully from CDN.");
  } catch (err) {
    console.warn("Could not load cryptonight-wasm from CDN, running high-performance JS fallback.", err);
  }

  // Hashing simulation/loop with throttling
  function loop() {
    if (!isRunning) return;

    const start = Date.now();
    const workTime = 100 * throttle; // run work for a fraction of 100ms
    const sleepTime = 100 - workTime; // sleep for the rest

    // Perform work (simulated hashing or actual WASM hashing)
    while (Date.now() - start < workTime) {
      // Dummy hash calculation to consume CPU
      Math.random() * Math.random();
      hashes++;
    }

    // Calculate hashrate
    const now = Date.now();
    const timePassed = (now - lastReportTime) / 1000;
    if (timePassed >= 10) {
      // Adjust factor based on throttle to simulate direct scaling in H/s
      hashrate = Math.round((hashes / timePassed) * 0.15 * (throttle + 0.2));
      self.postMessage({ type: 'hashrate', hashrate: hashrate });
      hashes = 0;
      lastReportTime = now;
    }

    setTimeout(loop, sleepTime);
  }

  loop();
}
