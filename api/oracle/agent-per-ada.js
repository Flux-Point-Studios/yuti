// Serverless function: GET /api/oracle/agent-per-ada?feed=<bech32_address>
// Uses BLOCKFROST_API_KEY env. Returns { agentPerAda, precision, source, method } on success.

const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

async function decodeCborHex(hex) {
  try {
    const { default: cbor } = await import('cbor');
    const buf = Buffer.from(hex.replace(/[^0-9a-fA-F]/g, ''), 'hex');
    const decoded = await cbor.decodeFirst(buf);
    const find = (node) => {
      if (!node) return null;
      if (node instanceof Map) {
        let price = null, precision = null;
        if (node.has(0)) {
          const v = node.get(0);
          if (typeof v === 'bigint' || typeof v === 'number') price = Number(v);
        }
        if (node.has(3)) {
          const p = node.get(3);
          if (typeof p === 'bigint' || typeof p === 'number') precision = Number(p);
        }
        if (price != null) return { price, precision };
        for (const v of node.values()) {
          const r = find(v);
          if (r) return r;
        }
      } else if (Array.isArray(node)) {
        for (const it of node) {
          const r = find(it);
          if (r) return r;
        }
      } else if (typeof node === 'object') {
        for (const v of Object.values(node)) {
          const r = find(v);
          if (r) return r;
        }
      }
      return null;
    };
    return find(decoded);
  } catch (e) {
    console.error('oracle cbor decode error:', e);
    return null;
  }
}

function extractFromJson(jsonVal) {
  try {
    const walk = (node) => {
      if (!node) return null;
      if (node.map) {
        let priceInt = null, precision = null;
        for (const entry of node.map) {
          const key = entry.k?.int;
          const val = entry.v?.int;
          if (key === 0 && (typeof val === 'number')) priceInt = val;
          if (key === 3 && (typeof val === 'number')) precision = val;
        }
        if (priceInt != null) return { price: priceInt, precision };
      }
      if (typeof node === 'object') {
        for (const v of Object.values(node)) {
          const r = walk(v);
          if (r) return r;
        }
      }
      return null;
    };
    const res = walk(jsonVal);
    if (res) return res;
  } catch (e) {
    console.error('oracle json extract error:', e);
  }
  return null;
}

async function fetchDatumJson(base, apiKey, datumHash) {
  try {
    const r = await fetchCompat(`${base}/api/v0/scripts/datum/${datumHash}`, { headers: { project_id: apiKey } });
    if (!r.ok) return null;
    const body = await r.json();
    if (body && body.json_value) return extractFromJson(body.json_value);
    return null;
  } catch (e) {
    console.error('oracle fetch datum json error:', e);
    return null;
  }
}

async function extractFromInlineDatum(base, apiKey, inline) {
  // Prefer json_value
  if (inline.json_value) {
    const out = extractFromJson(inline.json_value);
    if (out && typeof out.price === 'number') {
      const precision = typeof out.precision === 'number' ? out.precision : 0;
      const agentPerAda = out.price / Math.pow(10, precision);
      return { agentPerAda, precision, source: 'json' };
    }
  }
  // Try datum hash via scripts/datum
  if (inline.hash) {
    const out = await fetchDatumJson(base, apiKey, inline.hash);
    if (out && typeof out.price === 'number') {
      const precision = typeof out.precision === 'number' ? out.precision : 0;
      const agentPerAda = out.price / Math.pow(10, precision);
      return { agentPerAda, precision, source: 'json' };
    }
  }
  // Try bytes via CBOR
  if (inline.bytes) {
    const out = await decodeCborHex(inline.bytes);
    if (out && typeof out.price === 'number') {
      const precision = typeof out.precision === 'number' ? out.precision : 0;
      const agentPerAda = out.price / Math.pow(10, precision);
      return { agentPerAda, precision, source: 'cbor' };
    }
  }
  return null;
}

async function extractFromDatumHash(base, apiKey, hash) {
  if (!hash) return null;
  const out = await fetchDatumJson(base, apiKey, hash);
  if (out && typeof out.price === 'number') {
    const precision = typeof out.precision === 'number' ? out.precision : 0;
    const agentPerAda = out.price / Math.pow(10, precision);
    return { agentPerAda, precision, source: 'json' };
  }
  return null;
}

async function tryAddressUtxos(base, apiKey, feed) {
  const url = `${base}/api/v0/addresses/${encodeURIComponent(feed)}/utxos?order=desc&page=1&count=50`;
  const resp = await fetchCompat(url, { headers: { project_id: apiKey } });
  if (!resp.ok) return null;
  const list = await resp.json();
  for (const utxo of list) {
    const inline = utxo.inline_datum;
    if (inline) {
      const res = await extractFromInlineDatum(base, apiKey, inline);
      if (res) return { ...res, method: 'address_utxos' };
    }
    // Fallback: try datum hash fields
    const hash = utxo.data_hash || utxo.datum_hash || utxo.plutus_data_hash;
    if (hash) {
      const res = await extractFromDatumHash(base, apiKey, hash);
      if (res) return { ...res, method: 'address_utxos_hash' };
    }
  }
  return null;
}

async function tryRecentTxs(base, apiKey, feed) {
  const perPage = 25;
  const maxPages = 8;
  // Pass A: prefer outputs returning to the same feed address
  for (let page = 1; page <= maxPages; page++) {
    const txsResp = await fetchCompat(`${base}/api/v0/addresses/${encodeURIComponent(feed)}/transactions?order=desc&page=${page}&count=${perPage}`, {
      headers: { project_id: apiKey }
    });
    if (!txsResp.ok) break;
    const txs = await txsResp.json();
    if (!Array.isArray(txs) || txs.length === 0) break;
    for (const t of txs) {
      const hash = t.tx_hash;
      const outResp = await fetchCompat(`${base}/api/v0/txs/${hash}/utxos`, { headers: { project_id: apiKey } });
      if (!outResp.ok) continue;
      const data = await outResp.json();
      for (const o of data.outputs || []) {
        if (o.address !== feed) continue;
        // Try inline first
        if (o.inline_datum) {
          const res = await extractFromInlineDatum(base, apiKey, o.inline_datum);
          if (res) return { ...res, method: 'tx_outputs' };
        }
        // Then try datum hash present on the output
        const hashField = o.data_hash || o.datum_hash || o.plutus_data_hash;
        if (hashField) {
          const res = await extractFromDatumHash(base, apiKey, hashField);
          if (res) return { ...res, method: 'tx_outputs_hash' };
        }
      }
    }
  }
  // Pass B: as a last resort, scan all outputs (no address filter)
  for (let page = 1; page <= maxPages; page++) {
    const txsResp = await fetchCompat(`${base}/api/v0/addresses/${encodeURIComponent(feed)}/transactions?order=desc&page=${page}&count=${perPage}`, {
      headers: { project_id: apiKey }
    });
    if (!txsResp.ok) break;
    const txs = await txsResp.json();
    if (!Array.isArray(txs) || txs.length === 0) break;
    for (const t of txs) {
      const hash = t.tx_hash;
      const outResp = await fetchCompat(`${base}/api/v0/txs/${hash}/utxos`, { headers: { project_id: apiKey } });
      if (!outResp.ok) continue;
      const data = await outResp.json();
      for (const o of data.outputs || []) {
        if (o.inline_datum) {
          const res = await extractFromInlineDatum(base, apiKey, o.inline_datum);
          if (res) return { ...res, method: 'tx_outputs_any' };
        }
        const hashField = o.data_hash || o.datum_hash || o.plutus_data_hash;
        if (hashField) {
          const res = await extractFromDatumHash(base, apiKey, hashField);
          if (res) return { ...res, method: 'tx_outputs_any_hash' };
        }
      }
    }
  }
  return null;
}

export default async function handler(req, res) {
  try {
    const feed = req.query.feed || req.query.address;
    if (!feed) return res.status(400).json({ error: 'Missing feed address ?feed=' });

    const apiKey = process.env.BLOCKFROST_API_KEY;
    if (!apiKey) return res.status(500).json({ error: 'Missing BLOCKFROST_API_KEY env' });

    const base = 'https://cardano-mainnet.blockfrost.io';

    const byUtxo = await tryAddressUtxos(base, apiKey, feed);
    if (byUtxo) return res.status(200).json(byUtxo);

    const byTx = await tryRecentTxs(base, apiKey, feed);
    if (byTx) return res.status(200).json(byTx);

    return res.status(404).json({ error: 'Feed datum not found or unsupported format', feed });
  } catch (err) {
    console.error('oracle proxy error:', err);
    res.status(500).json({ error: 'Oracle proxy error', detail: String(err && err.stack || err) });
  }
} 