const supabase = require('./supabase');

const MEMORY_USERS = {
  'tjpoisal@gmail.com': {
    id: 'tim-001', name: 'Tim', email: 'tjpoisal@gmail.com',
    plan: 'pro', planExpires: null, createdAt: '2026-01-01T00:00:00Z',
  },
  'tim@getstackmax.com': {
    id: 'tim-002', name: 'Tim', email: 'tim@getstackmax.com',
    plan: 'pro', planExpires: null, createdAt: '2026-01-01T00:00:00Z',
  },
};

const hasSupabase = () => !!(supabase);

async function getUser(email) {
  const lower = email.toLowerCase().trim();
  if (!hasSupabase()) return MEMORY_USERS[lower] ?? null;
  const { data, error } = await supabase.from('rw_users').select('*').eq('email', lower).single();
  if (error && error.code !== 'PGRST116') throw error;
  return data ?? null;
}

async function grantPro(email, stripeCustomerId = null) {
  const lower = email.toLowerCase().trim();
  if (!hasSupabase()) {
    MEMORY_USERS[lower] = {
      ...(MEMORY_USERS[lower] || { id: Date.now().toString(), name: lower.split('@')[0], createdAt: new Date().toISOString() }),
      email: lower, plan: 'pro', planExpires: null, stripeCustomerId,
    };
    return MEMORY_USERS[lower];
  }
  const { data, error } = await supabase.from('rw_users')
    .upsert({ email: lower, plan: 'pro', plan_expires: null, stripe_customer_id: stripeCustomerId, updated_at: new Date().toISOString() }, { onConflict: 'email' })
    .select().single();
  if (error) throw error;
  return data;
}

async function revokePro(email) {
  const lower = email.toLowerCase().trim();
  if (!hasSupabase()) { if (MEMORY_USERS[lower]) MEMORY_USERS[lower].plan = 'free'; return; }
  await supabase.from('rw_users').update({ plan: 'free', updated_at: new Date().toISOString() }).eq('email', lower);
}

async function createUser(email, name = '') {
  const lower = email.toLowerCase().trim();
  if (!hasSupabase()) {
    if (!MEMORY_USERS[lower]) {
      MEMORY_USERS[lower] = {
        id: Date.now().toString(), name: name || lower.split('@')[0],
        email: lower, plan: 'free', planExpires: null, createdAt: new Date().toISOString(),
      };
    }
    return MEMORY_USERS[lower];
  }
  const { data, error } = await supabase.from('rw_users')
    .upsert({ email: lower, name: name || lower.split('@')[0], plan: 'free', created_at: new Date().toISOString(), updated_at: new Date().toISOString() }, { onConflict: 'email' })
    .select().single();
  if (error) throw error;
  return data;
}

module.exports = { getUser, grantPro, revokePro, createUser, hasSupabase };
