import { sql } from "drizzle-orm";
import { index, integer, real, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const trips = sqliteTable("trips", {
  id: text("id").primaryKey(),
  code: text("code").notNull().unique(),
  accessToken: text("access_token").notNull().unique(),
  visitorName: text("visitor_name").notNull(),
  emergencyPhone: text("emergency_phone"),
  routeName: text("route_name").notNull(),
  expectedReturnAt: text("expected_return_at").notNull(),
  status: text("status").notNull().default("active"),
  startedAt: text("started_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  completedAt: text("completed_at"),
}, (table) => [
  index("idx_trips_status_expected_return").on(table.status, table.expectedReturnAt),
]);

export const locationUpdates = sqliteTable("location_updates", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  tripId: text("trip_id").notNull().references(() => trips.id),
  latitude: real("latitude").notNull(),
  longitude: real("longitude").notNull(),
  accuracyMeters: real("accuracy_meters"),
  altitudeMeters: real("altitude_meters"),
  batteryPercent: integer("battery_percent"),
  recordedAt: text("recorded_at").notNull(),
  receivedAt: text("received_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  index("idx_locations_trip_recorded").on(table.tripId, table.recordedAt),
]);

export const alerts = sqliteTable("alerts", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  tripId: text("trip_id").notNull().references(() => trips.id),
  kind: text("kind").notNull(),
  message: text("message").notNull(),
  resolvedAt: text("resolved_at"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  index("idx_alerts_open_trip").on(table.resolvedAt, table.tripId),
]);
