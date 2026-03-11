const express = require('express');
const axios   = require('axios');
const router  = express.Router();

const NOAA_BASE = 'https://api.weather.gov';
const HEADERS   = { 'User-Agent': 'ResilienceWeatherWeb/1.0 (tim@getstackmax.com)' };

// GET /weather/point?lat=35.08&lon=-106.65
router.get('/point', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon required' });
  try {
    const point = await axios.get(`${NOAA_BASE}/points/${lat},${lon}`, { headers: HEADERS });
    const { gridId, gridX, gridY, relativeLocation } = point.data.properties;
    const city = relativeLocation?.properties?.city ?? '';
    const state = relativeLocation?.properties?.state ?? '';

    const [forecast, alerts] = await Promise.allSettled([
      axios.get(`${NOAA_BASE}/gridpoints/${gridId}/${gridX},${gridY}/forecast`, { headers: HEADERS }),
      axios.get(`${NOAA_BASE}/alerts/active?point=${lat},${lon}`, { headers: HEADERS }),
    ]);

    const periods = forecast.status === 'fulfilled'
      ? forecast.value.data.properties.periods.slice(0, 14)
      : [];

    const activeAlerts = alerts.status === 'fulfilled'
      ? alerts.value.data.features.map((f) => ({
          event: f.properties.event,
          severity: f.properties.severity,
          headline: f.properties.headline,
          description: f.properties.description?.slice(0, 300),
        }))
      : [];

    // Determine signal
    let signal = 'safe';
    const severeKeywords = ['tornado','hurricane','flash flood','extreme'];
    const warnKeywords = ['warning','watch'];
    for (const a of activeAlerts) {
      const t = (a.event + a.headline).toLowerCase();
      if (severeKeywords.some(k => t.includes(k))) { signal = 'extreme'; break; }
      if (warnKeywords.some(k => t.includes(k))) signal = 'warning';
    }
    if (activeAlerts.length > 0 && signal === 'safe') signal = 'caution';

    res.json({ city, state, signal, periods, alerts: activeAlerts, lat, lon });
  } catch (e) {
    res.status(500).json({ error: 'NOAA fetch failed', detail: e.message });
  }
});

// GET /weather/radar?lat=&lon= — returns radar station closest to point
router.get('/radar', async (req, res) => {
  const { lat, lon } = req.query;
  if (!lat || !lon) return res.status(400).json({ error: 'lat and lon required' });
  try {
    const point = await axios.get(`${NOAA_BASE}/points/${lat},${lon}`, { headers: HEADERS });
    const { radarStation } = point.data.properties;
    res.json({
      station: radarStation,
      url: `https://radar.weather.gov/station/${radarStation}/standard`,
      img: `https://radar.weather.gov/ridge/standard/${radarStation}_0.gif`,
    });
  } catch (e) {
    res.status(500).json({ error: 'Radar fetch failed' });
  }
});

module.exports = router;
