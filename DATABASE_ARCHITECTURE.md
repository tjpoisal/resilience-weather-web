# Database Architecture — SEPARATE & ISOLATED

## Resilience Weather
**Database:** AWS RDS PostgreSQL (resilience-weather-db)
**Host:** resilience-weather-db.cyn4cmaicl56.us-east-1.rds.amazonaws.com:5432
**Database Name:** resilience_db
**User:** resilience_admin
**Tables:** users, observations, subscriptions, alerts_cache, stripe_events, audit_log, operational_profiles
**Purpose:** NOAA emergency preparedness
**Grant Compliance:** NOAA-NWS-2024-28059

## StackMax
**Database:** Neon PostgreSQL (SEPARATE from Resilience Weather)
**Path:** /Users/timpoisal/code/STACKMAX-IDE-FINAL
**Database Name:** stackmax_db (at Neon, NOT AWS RDS)
**Purpose:** Fintech savings/extreme couponing platform
**Tables:** users, transactions, cashback_events, credit_stack, reward_tracking
**Deployment:** Render (stackmax-backend.onrender.com)

## CRITICAL RULE
🚫 **NEVER mix databases between products**
✅ Resilience Weather = AWS RDS (isolated)
✅ StackMax = Neon PostgreSQL (isolated)
✅ Different schemas
✅ Different compliance requirements
✅ Different scaling patterns

## Connection Strings (DO NOT MIX)

### Resilience Weather (AWS RDS)
```
postgresql://resilience_admin:vXulRTZ0eeAK9jvBmIVRljCv@resilience-weather-db.cyn4cmaicl56.us-east-1.rds.amazonaws.com:5432/resilience_db
```

### StackMax (Neon - separate account)
```
postgresql://[neon_user]:[neon_password]@[neon_host]/stackmax_db
```

🔒 Each product has its own isolated database.
