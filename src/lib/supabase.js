// Supabase client — gracefully handles missing env vars (memory-mode fallback)
const { createClient } = require('@supabase/supabase-js');

const url = process.env.SUPABASE_URL || '';
const key = process.env.SUPABASE_SERVICE_KEY || '';

// Only init supabase if both vars are set; otherwise export null (users.js handles fallback)
const supabase = (url && key && url !== 'your-supabase-url')
  ? createClient(url, key)
  : null;

module.exports = supabase;
