// Sample Node.js application placeholder
// This represents a service, cloud function, or lambda compiled/bundled by the CI pipeline.

console.log("Starting Sample App...");

const http = require("http");

const HTTP_OK = 200;
const DEFAULT_PORT = 3000;

const server = http.createServer((req, res) => {
  res.writeHead(HTTP_OK, { "Content-Type": "application/json" });
  res.end(
    JSON.stringify({
      message: "Hello from the homelab-infra sample application!",
      status: "healthy",
      timestamp: new Date().toISOString(),
    }),
  );
});

const PORT = process.env.PORT || DEFAULT_PORT;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
