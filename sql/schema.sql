-- Resilience Weather PostgreSQL Schema
-- Federal compliance enabled (CloudTrail logging via app triggers)
-- Multi-AZ backup enabled (RDS managed)

-- ────────────────────────────────────────
-- USERS TABLE
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) NOT NULL UNIQUE,
  stripe_customer_id VARCHAR(255),
  stripe_subscription_id VARCHAR(255),
  plan VARCHAR(50) DEFAULT 'free' CHECK (plan IN ('free', 'pro', 'enterprise')),
  operational_profile VARCHAR(255),
  preferences JSONB,
  name VARCHAR(255),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_stripe_customer ON users(stripe_customer_id);
CREATE INDEX idx_users_plan ON users(plan);

-- ────────────────────────────────────────
-- OBSERVATIONS TABLE
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  latitude DECIMAL(10, 6) NOT NULL,
  longitude DECIMAL(10, 6) NOT NULL,
  temperature DECIMAL(5, 2),
  temperature_unit VARCHAR(1) DEFAULT 'F',
  conditions VARCHAR(255) NOT NULL,
  wind_speed DECIMAL(5, 2),
  wind_direction VARCHAR(3),
  humidity DECIMAL(5, 2),
  pressure DECIMAL(7, 2),
  precipitation DECIMAL(5, 2),
  visibility DECIMAL(5, 2),
  uv_index DECIMAL(3, 1),
  notes TEXT,
  image_url VARCHAR(2048),
  verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_observations_user ON observations(user_id);
CREATE INDEX idx_observations_location ON observations(latitude, longitude);
CREATE INDEX idx_observations_created ON observations(created_at);

-- ────────────────────────────────────────
-- SUBSCRIPTIONS TABLE
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  latitude DECIMAL(10, 6) NOT NULL,
  longitude DECIMAL(10, 6) NOT NULL,
  alert_types TEXT[] DEFAULT ARRAY['severe_weather', 'flood', 'heat', 'wind'],
  push_enabled BOOLEAN DEFAULT TRUE,
  email_enabled BOOLEAN DEFAULT FALSE,
  sms_enabled BOOLEAN DEFAULT FALSE,
  notification_frequency VARCHAR(50) DEFAULT 'immediate',
  preferences JSONB,
  last_alert_sent_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_location ON subscriptions(latitude, longitude);

-- ────────────────────────────────────────
-- ALERTS CACHE
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS alerts_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  noaa_id VARCHAR(255) UNIQUE,
  event VARCHAR(255) NOT NULL,
  headline TEXT,
  description TEXT,
  severity VARCHAR(50),
  effective TIMESTAMP WITH TIME ZONE,
  expires TIMESTAMP WITH TIME ZONE,
  area_desc VARCHAR(500),
  properties JSONB,
  cached_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_alerts_noaa_id ON alerts_cache(noaa_id);
CREATE INDEX idx_alerts_expires ON alerts_cache(expires_at);

-- ────────────────────────────────────────
-- STRIPE EVENTS LOG (Audit trail)
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS stripe_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id VARCHAR(255) UNIQUE NOT NULL,
  event_type VARCHAR(255) NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  stripe_customer_id VARCHAR(255),
  stripe_subscription_id VARCHAR(255),
  data JSONB,
  processed BOOLEAN DEFAULT FALSE,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_stripe_events_type ON stripe_events(event_type);
CREATE INDEX idx_stripe_events_user ON stripe_events(user_id);
CREATE INDEX idx_stripe_events_processed ON stripe_events(processed);

-- ────────────────────────────────────────
-- AUDIT LOG (Federal compliance)
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(255) NOT NULL,
  resource_type VARCHAR(255),
  resource_id VARCHAR(255),
  details JSONB,
  ip_address VARCHAR(45),
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_user ON audit_log(user_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_created ON audit_log(created_at);

-- ────────────────────────────────────────
-- OPERATIONAL PROFILES (15 predefined)
-- ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS operational_profiles (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  description TEXT,
  alert_categories TEXT[],
  data_retention_days INT DEFAULT 30,
  mesh_networking BOOLEAN DEFAULT FALSE,
  offline_first BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO operational_profiles (name, description, alert_categories)
VALUES
  ('General Public', 'Daily forecasts and severe weather alerts', ARRAY['severe_weather', 'flood']),
  ('Marine / Fisher', 'Coastal, wind, and wave data', ARRAY['marine', 'wind', 'coastal_hazards']),
  ('Agricultural', 'Frost, drought, precipitation, UV', ARRAY['frost', 'drought', 'precipitation', 'uv']),
  ('Aviation / Drone', 'Wind shear, visibility, ceiling', ARRAY['wind_shear', 'visibility', 'icing']),
  ('Neurodivergent', 'Sensory-friendly alerts, minimal notifications', ARRAY['severe_weather']),
  ('Universal / Zero-Literacy', 'Icons and audio, no text', ARRAY['severe_weather', 'flood']),
  ('City / Urban Health', 'Air quality, heat index, pollen', ARRAY['air_quality', 'heat', 'pollen']),
  ('Post-Disaster Recovery', 'Infrastructure impact, road closures', ARRAY['infrastructure', 'road_closure']),
  ('Commuter / Logistics', 'Transit delays, congestion, visibility', ARRAY['transit_impact', 'visibility']),
  ('Event Organizer', 'Multi-location, group alerts', ARRAY['severe_weather', 'crowd_safety']),
  ('Family / Multi-Location', 'Alerts for multiple family members', ARRAY['severe_weather', 'flood']),
  ('Renewable Energy / Grid', 'Wind speed, solar irradiance, grid stability', ARRAY['wind', 'solar', 'grid_stability']),
  ('Construction / Safety', 'High wind, lightning, visibility', ARRAY['wind', 'lightning', 'visibility']),
  ('Tribal / Arctic', 'Subsistence species migration, ice conditions', ARRAY['ice', 'migration']),
  ('Citizen Science', 'Observation sharing, network contribution', ARRAY['all'])
ON CONFLICT DO NOTHING;
