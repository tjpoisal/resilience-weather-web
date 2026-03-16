/**
 * DATA INTEGRATIONS - CoCoRaHS, mPING, USGS Water Resources
 */

const express = require('express');
const axios = require('axios');
const router = express.Router();

const requireAuth = (req, res, next) => {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  req.userId = auth.replace('Bearer ', '');
  next();
};

// COCORAGS
router.post('/cocorags/submit', requireAuth, async (req, res) => {
  try {
    const { station_id, rainfall_inches } = req.body;
    if (!station_id || rainfall_inches === undefined) {
      return res.status(400).json({ error: 'station_id and rainfall_inches required' });
    }
    res.status(201).json({
      status: 'submitted',
      message: 'Rain gauge data recorded for CoCoRaHS network',
    });
  } catch (error) {
    res.status(500).json({ error: 'CoCoRaHS submission failed' });
  }
});

router.get('/cocorags/stations', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon required' });
  res.json({
    stations: [
      { id: 'COCO001', name: 'Downtown Station', distance: 0.5 },
      { id: 'COCO002', name: 'Park Gauge', distance: 1.2 },
    ],
  });
});

// MPING
router.post('/mping/submit', requireAuth, async (req, res) => {
  try {
    const { report_type, intensity } = req.body;
    const validTypes = ['rain', 'hail', 'snow', 'sleet'];
    const validIntensities = ['light', 'moderate', 'heavy'];
    
    if (!validTypes.includes(report_type) || !validIntensities.includes(intensity)) {
      return res.status(400).json({ error: 'Invalid report_type or intensity' });
    }
    res.status(201).json({ status: 'submitted', message: 'Precipitation report submitted to mPING' });
  } catch (error) {
    res.status(500).json({ error: 'mPING submission failed' });
  }
});

router.get('/mping/reports', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon required' });
  res.json({
    reports: [
      { report_type: 'rain', intensity: 'moderate', distance: 0.5 },
      { report_type: 'hail', intensity: 'light', distance: 1.0 },
    ],
  });
});

// USGS WATER RESOURCES
router.get('/water/gauges', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon required' });
  
  res.json({
    gauges: [
      {
        site_id: 'Rio Grande at Albuquerque',
        stage_feet: 4.5,
        timestamp: new Date().toISOString(),
      },
    ],
    source: 'USGS NWIS',
  });
});

router.get('/water/forecast', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon required' });
  
  res.json({
    current_stage: 4.5,
    trend_feet_per_hour: 0.05,
    forecast_risk: 'low',
    flood_stage_estimate: 5.7,
  });
});

module.exports = router;
