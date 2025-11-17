import { Pool } from 'pg';

// Expected env:
//   DBSYNC_URL = postgresql://user:pass@host:5432/dbname
// Optional:
//   DBSYNC_SSL = 'require' | 'disable'

let pool;
function getPool() {
  if (!pool) {
    const connectionString = process.env.DBSYNC_URL;
    if (!connectionString) {
      throw new Error('Missing DBSYNC_URL env');
    }
    const sslMode = (process.env.DBSYNC_SSL || 'require').toLowerCase();
    const ssl =
      sslMode === 'disable'
        ? false
        : { rejectUnauthorized: false };
    pool = new Pool({ connectionString, ssl });
  }
  return pool;
}

export default async function handler(req, res) {
  try {
    const { address, page } = req.query || {};
    if (!address || typeof address !== 'string') {
      res.status(400).json({ error: 'Missing address' });
      return;
    }
    const pageNum = Math.max(1, parseInt(page || '1', 10) || 1);
    const pageSize = 50;
    const offset = (pageNum - 1) * pageSize;

    const sql = `
      with addr as (
        select $1::text as address
      ),
      outs as (
        select tx_out.tx_id, tx_out.index
        from tx_out
        join addr on tx_out.address = addr.address
      ),
      ins as (
        select tx_in.tx_in_id as tx_id
        from tx_in
        join tx_out on tx_in.tx_out_id = tx_out.tx_id and tx_in.tx_out_index = tx_out.index
        join addr on tx_out.address = addr.address
      ),
      touched as (
        select tx_id from outs
        union
        select tx_id from ins
      )
      select
        encode(tx.hash, 'hex') as tx_hash,
        block.block_no as block_height,
        to_char((block.time at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as block_time
      from tx
      join block on block.id = tx.block_id
      join touched on touched.tx_id = tx.id
      order by block.time desc
      limit $2 offset $3
    `;

    const client = await getPool().connect();
    try {
      const r = await client.query(sql, [address, pageSize, offset]);
      res.setHeader('Cache-Control', 's-maxage=15, stale-while-revalidate=60');
      res.status(200).json(r.rows || []);
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('dbsync/transactions error:', err);
    res.status(500).json({ error: 'dbsync query error', detail: String(err && err.message || err) });
  }
}


