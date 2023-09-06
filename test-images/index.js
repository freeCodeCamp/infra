const http = require('http');
const port = 3000;

const server = http.createServer((req, res) => {
    const startTime = Date.now();

    res.on('finish', () => {  // This event will fire once the response is done
        const endTime = Date.now();
        const responseTime = endTime - startTime;
        const clientIP = req.headers['client-ip'] || req.connection.remoteAddress;
        console.log(
            `[${new Date(startTime).toISOString()}] - Method: ${req.method} - URL: ${req.url} - IP: ${clientIP} - Response Time: ${responseTime}ms`
        );
    });

    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/plain')
    res.end('Hello World\n');
});

server.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});

process.on('SIGINT', () => {
    console.log('Shutting down server');
    server.close();
    process.exit();
});

