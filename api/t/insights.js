export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const baseUrl = process.env.T_BACKEND_URL || 'https://api.fluxpointstudios.com';
    const apiKey = process.env.T_BACKEND_API_KEY || '';

    if (!apiKey) {
      res.status(500).json({ error: 'Missing T_BACKEND_API_KEY env' });
      return;
    }

    const unit = (req.query.unit || '').toString();
    const name = (req.query.name || '').toString();
    const sessionId = 'wallet_insights';

    if (!unit) {
      res.status(400).json({ error: 'Missing unit' });
      return;
    }

    const message = `Give a brief overview (max 6 lines) about Cardano asset "${name || unit}" with unit "${unit}". Include what it is, notable utility, and any relevant resources. Use bullet points.`;

    const targetUrl = `${baseUrl.replace(/\/$/, '')}/chat`;
    const upstream = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': apiKey,
      },
      body: JSON.stringify({
        message,
        session_id: sessionId,
        context: { asset_unit: unit, asset_name: name || unit },
      }),
    });

    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    // Cache for all users for 12 hours, allow stale while revalidating
    res.setHeader('Cache-Control', 's-maxage=43200, stale-while-revalidate=86400');
    res.send(text);
  } catch (err) {
    console.error('Insights proxy error /api/t/insights:', err);
    res.status(500).json({ error: 'Proxy error', detail: String((err && err.stack) || err) });
  }
} 