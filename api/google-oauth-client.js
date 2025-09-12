export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    const clientId = process.env.SMART_WALLET_GOOGLE_WEB_CLIENT_ID || '';
    if (!clientId) {
      res.status(404).json({ error: 'Not configured' });
      return;
    }
    res.status(200).json({ client_id: clientId });
  } catch (err) {
    res.status(500).json({ error: 'google oauth client error', detail: String(err && err.stack || err) });
  }
} 