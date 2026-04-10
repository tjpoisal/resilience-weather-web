#!/usr/bin/env node

/**
 * Database initialization script
 * Runs on app startup to ensure schema exists
 */

const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

const DB_HOST = process.env.DB_HOST || 'resilience-weather-db.cyn4cmaicl56.us-east-1.rds.amazonaws.com';
const DB_PORT = process.env.DB_PORT || 5432;
const DB_NAME = process.env.DB_NAME || 'resilience_db';
const DB_USER = process.env.DB_USER || 'resilience_admin';
const DB_PASSWORD = process.env.DB_PASSWORD || '';

async function initializeDatabase() {
  const client = new Client({
    host: DB_HOST,
    port: DB_PORT,
    database: DB_NAME,
    user: DB_USER,
    password: DB_PASSWORD,
    ssl: { rejectUnauthorized: false }
  });

  try {
    console.log('📍 Connecting to RDS PostgreSQL...');
    await client.connect();
    console.log('✅ Connected');

    // Check if schema already exists
    const schemaCheckResult = await client.query(
      `SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users');`
    );

    if (schemaCheckResult.rows[0].exists) {
      console.log('✅ Schema already initialized');
      await client.end();
      return;
    }

    console.log('📍 Initializing schema...');
    const schemaPath = path.join(__dirname, '../sql/schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf8');

    await client.query(schema);
    console.log('✅ Schema initialized successfully');

    const tablesResult = await client.query(
      `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;`
    );

    console.log('📊 Created tables:');
    tablesResult.rows.forEach((row) => {
      console.log(`   • ${row.table_name}`);
    });

    await client.end();
  } catch (error) {
    console.error('❌ Database initialization failed:');
    console.error(error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  initializeDatabase().catch((error) => {
    console.error('Initialization error:', error);
    process.exit(1);
  });
}

module.exports = initializeDatabase;
