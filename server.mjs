import http from 'http';

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');

  if (req.url === '/healthy') {
    res.writeHead(200);
    res.end('{"status":"ok","service":"healthy","uptime":"99.99%"}');
  } else if (req.url === '/down') {
    res.writeHead(500);
    res.end('{"error":"Internal Server Error","service":"down","message":"Database connection pool exhausted"}');
  } else if (req.url === '/slow') {
    setTimeout(() => {
      res.writeHead(200);
      res.end('{"status":"ok","service":"slow","message":"Response delayed by 8 seconds"}');
    }, 8000);
  } else if (req.url === '/flapping') {
    if (Math.random() < 0.5) {
      res.writeHead(200);
      res.end('{"status":"ok","service":"flapping"}');
    } else {
      res.writeHead(500);
      res.end('{"error":"Service Unavailable","service":"flapping"}');
    }
  } else if (req.url === '/random-errors') {
    if (Math.random() < 0.83) {
      res.writeHead(200);
      res.end('{"status":"ok","service":"random-errors"}');
    } else {
      res.writeHead(502);
      res.end('{"error":"Bad Gateway","service":"random-errors","message":"Upstream server unavailable"}');
    }
  } else {
    res.writeHead(404);
    res.end('{"error":"Not Found"}');
  }
});

server.listen(1080, () => {
  console.log('[mock] Listening on :1080');
});
