export default async function handler(req, res) {
  try {
    const baseUrl = process.env.T_BACKEND_URL || 'https://api-v2.fluxpointstudios.com';
    const apiKey = process.env.T_BACKEND_API_KEY || '';

    if (!apiKey) {
      res.status(500).json({ error: 'Missing T_BACKEND_API_KEY env' });
      return;
    }

    const targetUrl = `${baseUrl.replace(/\/$/, '')}/chat`;

    const upstream = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': apiKey,
      },
      body: typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {}),
    });

    const contentType = upstream.headers.get('content-type') || '';
    // If upstream is sending SSE, proxy chunks as they arrive
    if (contentType.includes('text/event-stream')) {
      res.status(upstream.status);
      res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
      res.setHeader('Cache-Control', 'no-cache, no-transform');
      res.setHeader('Connection', 'keep-alive');
      // Optional: CORS for local dev
      if (!res.getHeader('Access-Control-Allow-Origin')) {
        res.setHeader('Access-Control-Allow-Origin', '*');
      }
      // Stream body
      const reader = upstream.body?.getReader?.();
      if (!reader) {
        // Fallback if body is not a web stream
        const buf = Buffer.from(await upstream.arrayBuffer());
        res.write(buf);
        res.end();
        return;
      }
      // Pipe reader chunks to Node response
      try {
        // Send an initial comment to open the stream in some proxies
        res.write(': connected\n\n');
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (value && value.length) {
            res.write(Buffer.from(value));
          }
        }
      } catch (e) {
        // Swallow errors on broken client connections
      } finally {
        res.end();
      }
      return;
    }

    // Non-SSE: buffer and forward as-is
    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', contentType || 'application/json');
    res.send(text);
  } catch (err) {
    console.error('Proxy error /api/t/chat:', err);
    res.status(500).json({ error: 'Proxy error', detail: String(err && err.stack || err) });
  }
} 