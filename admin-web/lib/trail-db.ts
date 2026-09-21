import { env } from "cloudflare:workers";

export type TripRow = {
  id: string;
  code: string;
  visitorName: string;
  emergencyPhone: string | null;
  routeName: string;
  expectedReturnAt: string;
  startedAt: string;
  completedAt: string | null;
  status: string;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  batteryPercent: number | null;
  recordedAt: string | null;
  alertKind: string | null;
};

function db() {
  if (!env.DB) throw new Error("TrailWatch database is unavailable");
  return env.DB;
}

export async function listTrips() {
  const result = await db().prepare(`
    SELECT
      t.id, t.code, t.visitor_name AS visitorName,
      t.emergency_phone AS emergencyPhone, t.route_name AS routeName,
      t.expected_return_at AS expectedReturnAt, t.started_at AS startedAt,
      t.completed_at AS completedAt, t.status,
      l.latitude, l.longitude, l.accuracy_meters AS accuracyMeters,
      l.battery_percent AS batteryPercent, l.recorded_at AS recordedAt,
      a.kind AS alertKind
    FROM trips t
    LEFT JOIN location_updates l ON l.id = (
      SELECT id FROM location_updates WHERE trip_id = t.id ORDER BY recorded_at DESC LIMIT 1
    )
    LEFT JOIN alerts a ON a.id = (
      SELECT id FROM alerts WHERE trip_id = t.id AND resolved_at IS NULL ORDER BY created_at DESC LIMIT 1
    )
    ORDER BY CASE WHEN a.kind = 'sos' THEN 0 WHEN t.status = 'active' THEN 1 ELSE 2 END,
      t.expected_return_at ASC
    LIMIT 200
  `).all<TripRow>();
  return result.results;
}

export async function createTrip(input: { visitorName: string; emergencyPhone?: string; routeName: string; expectedMinutes: number }) {
  const id = crypto.randomUUID();
  const code = `TW-${crypto.randomUUID().replaceAll("-", "").slice(0, 8).toUpperCase()}`;
  const accessToken = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
  const expectedReturnAt = new Date(Date.now() + input.expectedMinutes * 60_000).toISOString();
  await db().prepare(`
    INSERT INTO trips (id, code, access_token, visitor_name, emergency_phone, route_name, expected_return_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).bind(id, code, accessToken, input.visitorName, input.emergencyPhone ?? null, input.routeName, expectedReturnAt).run();
  return { id, code, accessToken, visitorName: input.visitorName, routeName: input.routeName, expectedReturnAt };
}

export async function joinTrip(code: string) {
  return db().prepare(`
    SELECT id, code, access_token AS accessToken, visitor_name AS visitorName,
      route_name AS routeName, expected_return_at AS expectedReturnAt, status
    FROM trips WHERE UPPER(code) = UPPER(?) LIMIT 1
  `).bind(code).first<Record<string, string>>();
}

export async function authenticateTrip(tripId: string, token: string) {
  return db().prepare("SELECT id, status FROM trips WHERE id = ? AND access_token = ? LIMIT 1").bind(tripId, token).first<{ id: string; status: string }>();
}

export async function addLocation(input: { tripId: string; latitude: number; longitude: number; accuracyMeters?: number; altitudeMeters?: number; batteryPercent?: number; recordedAt: string }) {
  await db().prepare(`
    INSERT INTO location_updates (trip_id, latitude, longitude, accuracy_meters, altitude_meters, battery_percent, recorded_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).bind(input.tripId, input.latitude, input.longitude, input.accuracyMeters ?? null, input.altitudeMeters ?? null, input.batteryPercent ?? null, input.recordedAt).run();
}

export async function raiseSos(tripId: string, message: string) {
  await db().batch([
    db().prepare("UPDATE trips SET status = 'sos' WHERE id = ?").bind(tripId),
    db().prepare("INSERT INTO alerts (trip_id, kind, message) VALUES (?, 'sos', ?)").bind(tripId, message),
  ]);
}

export async function completeTrip(tripId: string) {
  await db().batch([
    db().prepare("UPDATE trips SET status = 'completed', completed_at = CURRENT_TIMESTAMP WHERE id = ?").bind(tripId),
    db().prepare("UPDATE alerts SET resolved_at = CURRENT_TIMESTAMP WHERE trip_id = ? AND resolved_at IS NULL").bind(tripId),
  ]);
}
