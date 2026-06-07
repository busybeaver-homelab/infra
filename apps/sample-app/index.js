// Sample Node.js application placeholder
// This represents a service, cloud function, or lambda compiled/bundled by the CI pipeline.

console.log("Starting Sample App...");

const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: "healthy",
    timestamp: new Date().toISOString(),
    message: "Hello from the homelab-infra sample application!"
  }));
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
