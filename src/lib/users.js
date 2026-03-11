// Pure in-memory user store — no database required
const USERS = {
  'tjpoisal@gmail.com': { id:'tim-001', name:'Tim', email:'tjpoisal@gmail.com', plan:'pro' },
  'tim@getstackmax.com': { id:'tim-002', name:'Tim', email:'tim@getstackmax.com', plan:'pro' },
};

async function getUser(email) {
  return USERS[email.toLowerCase().trim()] ?? null;
}
async function createUser(email, name='') {
  const lower = email.toLowerCase().trim();
  if (!USERS[lower]) {
    USERS[lower] = { id: Date.now().toString(), name: name||lower.split('@')[0], email: lower, plan:'free' };
  }
  return USERS[lower];
}
async function grantPro(email) {
  const lower = email.toLowerCase().trim();
  if (!USERS[lower]) await createUser(lower);
  USERS[lower].plan = 'pro';
  return USERS[lower];
}
async function revokePro(email) {
  const lower = email.toLowerCase().trim();
  if (USERS[lower]) USERS[lower].plan = 'free';
}

module.exports = { getUser, createUser, grantPro, revokePro };
