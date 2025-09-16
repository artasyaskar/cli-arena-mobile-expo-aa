// Mock GraphQL Subscription Server (Node.js + ws)
// Simulates Supabase GraphQL subscriptions over WebSockets.

const WebSocket = require('ws');
const http = require('http');
const url = require('url');

const PORT = process.env.MOCK_GRAPHQL_PORT || 8088; // Allow port override
const MOCK_API_KEY = 'test-supabase-api-key'; // For auth simulation

// In-memory representation of a simple database
let db = {
  users: [
    { id: '1', name: 'Alice Mock', email: 'alice@example.com', updated_at: new Date().toISOString() },
    { id: '2', name: 'Bob Mock', email: 'bob@example.com', updated_at: new Date().toISOString() },
  ],
  posts: [
    { id: 'p1', title: 'Hello World', content: 'First post!', userId: '1', updated_at: new Date().toISOString() },
  ]
};

// --- Server Setup ---
const server = http.createServer((req, res) => {
  // Basic HTTP endpoint for health check or info
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', message: 'Mock GraphQL Server is running' }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

const wss = new WebSocket.Server({ server });

console.log(`Mock GraphQL WebSocket Server started on ws://localhost:${PORT}`);
console.log(`API Key for testing: ${MOCK_API_KEY}`);

// Store active client subscriptions: ws -> { subId -> { query, variables, intervalId? } }
const clientSubscriptions = new Map();


// --- WebSocket Connection Handling ---
wss.on('connection', (ws, req) => {
  const queryObject = url.parse(req.url, true).query;
  const protocol = ws.protocol || (Array.isArray(req.headers['sec-websocket-protocol']) ? req.headers['sec-websocket-protocol'][0] : req.headers['sec-websocket-protocol']);


  console.log(`Client connected. Protocol: ${protocol}. URL query: ${JSON.stringify(queryObject)}`);
  ws.isAlive = true;
  clientSubscriptions.set(ws, {});

  let connectionInitialized = false;
  let clientApiKey = null;

  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (messageStr) => {
    console.log('Received message:', messageStr.toString());
    let message;
    try {
      message = JSON.parse(messageStr);
    } catch (e) {
      console.error('Failed to parse message JSON:', e);
      ws.send(JSON.stringify({ type: 'error', payload: { message: 'Invalid JSON message' } }));
      return;
    }

    switch (message.type) {
      case 'connection_init': // graphql-ws or graphql-transport-ws
        console.log('Received connection_init. Payload:', message.payload);
        // Simulate auth check
        clientApiKey = message.payload?.headers?.apikey || message.payload?.apiKey || message.payload?.Authorization?.split('Bearer ')[1];
        if (clientApiKey !== MOCK_API_KEY && queryObject.apikey !== MOCK_API_KEY) {
            // In graphql-transport-ws, error is sent before closing.
            // In older graphql-ws, connection_error might be sent, or just close.
            console.error(`Authentication failed. Expected key '${MOCK_API_KEY}', got '${clientApiKey || queryObject.apikey}'`);
            if (protocol === 'graphql-transport-ws') {
                 ws.send(JSON.stringify({ type: 'connection_error', payload: { message: 'Authentication failed' } }));
            }
            ws.close(1008, 'Authentication failed'); // Policy Violation
            return;
        }

        ws.send(JSON.stringify({ type: 'connection_ack' }));
        connectionInitialized = true;
        console.log('Sent connection_ack.');
        break;

      case 'ping': // graphql-transport-ws
        ws.send(JSON.stringify({ type: 'pong', payload: message.payload }));
        console.log('Sent pong.');
        break;

      case 'subscribe': // graphql-transport-ws
      case 'start':    // older graphql-ws (deprecated by many tools)
        if (!connectionInitialized) {
          ws.close(1002, 'Protocol error: subscribe before connection_init/ack');
          return;
        }
        const subId = message.id;
        const { query, variables, operationName } = message.payload;
        console.log(`Client wants to subscribe (ID: ${subId}): Query: ${query}, Vars: ${JSON.stringify(variables)}, OpName: ${operationName}`);

        if (!query || !subId) {
            ws.send(JSON.stringify({ id: subId, type: 'error', payload: { message: 'Missing query or ID for subscription.'}}));
            return;
        }

        const currentSubs = clientSubscriptions.get(ws);
        if (currentSubs[subId]) {
            ws.send(JSON.stringify({ id: subId, type: 'error', payload: { message: `Subscriber for ${subId} already exists`}}));
            return;
        }

        // Store subscription details
        currentSubs[subId] = { query, variables, operationName };

        // Simulate initial data push for 'usersCollection' (if query matches)
        if (query.includes('usersCollection')) {
          const initialData = { usersCollection: db.users.map(u => ({...u})) }; // Send copy
          ws.send(JSON.stringify({ id: subId, type: 'next', payload: { data: initialData } })); // graphql-transport-ws
          // ws.send(JSON.stringify({ id: subId, type: 'data', payload: { data: initialData } })); // older graphql-ws
          console.log(`Sent initial data for usersCollection to subId ${subId}`);

          // Simulate periodic updates for this subscription
          currentSubs[subId].intervalId = setInterval(() => {
            if (ws.readyState === WebSocket.OPEN) {
              const randomUserIndex = Math.floor(Math.random() * db.users.length);
              const userToUpdate = db.users[randomUserIndex];
              userToUpdate.name += ' Updated'; // Simulate an update
              userToUpdate.updated_at = new Date().toISOString();

              // Construct payload based on a simplified interpretation of the query
              // A real server would re-evaluate the GraphQL query against the updated data.
              const updatePayload = { usersCollection: [userToUpdate] }; // Simplified: just send the updated user in an array
                                                                         // More correct: send all users matching query

              ws.send(JSON.stringify({ id: subId, type: 'next', payload: { data: updatePayload } }));
              console.log(`Sent data update for usersCollection to subId ${subId}: ${userToUpdate.id}`);
            }
          }, 5000 + Math.random() * 2000); // Update every 5-7 seconds
        } else if (query.includes('postsCollection')) {
            const initialData = { postsCollection: db.posts.map(p => ({...p})) };
            ws.send(JSON.stringify({ id: subId, type: 'next', payload: { data: initialData } }));
            console.log(`Sent initial data for postsCollection to subId ${subId}`);
            // No periodic updates for posts in this mock for simplicity
        } else {
            ws.send(JSON.stringify({ id: subId, type: 'error', payload: { message: 'Mock server only supports subscriptions to "usersCollection" or "postsCollection"' } }));
        }
        break;

      case 'complete': // graphql-transport-ws
      case 'stop':     // older graphql-ws
        if (!connectionInitialized) {
          ws.close(1002, 'Protocol error: complete/stop before connection_init/ack');
          return;
        }
        const unsubId = message.id;
        console.log(`Client wants to unsubscribe (ID: ${unsubId})`);
        const clientSub = clientSubscriptions.get(ws)?.[unsubId];
        if (clientSub) {
          if (clientSub.intervalId) clearInterval(clientSub.intervalId);
          delete clientSubscriptions.get(ws)[unsubId];
          // No server-side 'complete' message is usually sent back for client-initiated stop,
          // unless the spec explicitly requires it for 'graphql-transport-ws'.
          // For 'graphql-ws' (older), no response.
          // 'graphql-transport-ws' spec says: "The server does not respond to the client's complete message."
          console.log(`Subscription ${unsubId} stopped.`);
        }
        break;

      default:
        console.warn('Unknown message type:', message.type);
        ws.send(JSON.stringify({ type: 'error', payload: { message: `Unknown message type: ${message.type}` } }));
    }
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
    // Cleanup subscriptions for this client
    const subs = clientSubscriptions.get(ws);
    if (subs) {
        for (const subId in subs) {
            if (subs[subId].intervalId) clearInterval(subs[subId].intervalId);
        }
    }
    clientSubscriptions.delete(ws);
  });

  ws.on('close', (code, reason) => {
    console.log(`Client disconnected. Code: ${code}, Reason: ${reason}`);
    // Cleanup subscriptions for this client
    const subs = clientSubscriptions.get(ws);
    if (subs) {
        for (const subId in subs) {
            if (subs[subId].intervalId) clearInterval(subs[subId].intervalId);
        }
    }
    clientSubscriptions.delete(ws);
  });
});


// Simulate server-initiated connection drop for one client after some time (for testing reconnect)
// setTimeout(() => {
//   if (wss.clients.size > 0) {
//     const firstClient = wss.clients.values().next().value;
//     if (firstClient) {
//       console.log("Simulating server drop for one client...");
//       firstClient.terminate(); // Abruptly close connection
//     }
//   }
// }, 20000); // After 20 seconds


// Keep-alive pings (for graphql-transport-ws, server can send Pings)
// For older graphql-ws, client might send keep-alive, server just responds if needed.
// This interval is for the server to check client aliveness.
const interval = setInterval(function ping() {
  wss.clients.forEach(function each(ws) {
    if (ws.isAlive === false) {
      console.log("Client not alive, terminating.");
      return ws.terminate();
    }
    ws.isAlive = false; // Will be set true on pong

    // Send ping based on protocol if needed (graphql-transport-ws)
    // if (ws.protocol === 'graphql-transport-ws') {
    //   console.log("Sending server Ping to client");
    //   ws.send(JSON.stringify({ type: 'ping' }));
    // } else {
       ws.ping(() => {}); // Standard WebSocket ping
    // }
  });
}, 30000); // Every 30 seconds

wss.on('close', function close() {
  clearInterval(interval);
});

server.listen(PORT, () => {
  console.log(`HTTP server for WebSocket upgrades listening on http://localhost:${PORT}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down mock server...');
  wss.clients.forEach(ws => {
    const subs = clientSubscriptions.get(ws);
    if (subs) {
        for (const subId in subs) {
            if (subs[subId].intervalId) clearInterval(subs[subId].intervalId);
        }
    }
    ws.close(1012, "Server shutting down"); // Service Restart
  });
  clientSubscriptions.clear();
  wss.close(() => {
    server.close(() => {
      console.log('Server closed.');
      process.exit(0);
    });
  });
});
