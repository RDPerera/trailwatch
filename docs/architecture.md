# TrailWatch architecture

## Components

1. The Flutter visitor app exchanges a ticket code for a trip-scoped access token.
2. Mobile API endpoints accept authenticated location, SOS, and completion events.
3. Cloudflare D1 stores trips, location history, and alerts.
4. The admin dashboard reads the latest update for each trip and derives operational status.

## API surface

- `POST /api/trips` — issue a new ticket
- `GET /api/trips` — list trips with latest locations and alerts
- `POST /api/mobile/join` — exchange a ticket code for the trip session
- `POST /api/mobile/location` — store a GPS and battery update
- `POST /api/mobile/sos` — create an emergency alert
- `POST /api/mobile/complete` — close the trip and resolve its alerts

Mobile writes require both the opaque trip ID and its randomly generated access token. Ticket codes are intended to be handed directly to the visitor and should be treated as temporary secrets.

## Production hardening backlog

- Put the public mobile API on an origin accessible without the private admin dashboard session.
- Protect all ranger write/read routes with staff authentication and park-level authorization.
- Add rate limiting, request-size limits, audit logs, and token rotation.
- Replace the stylized map with OpenStreetMap tiles and route geometry.
- Add background location services and platform-specific permission education.
- Add push notifications for SOS, overdue, stale signal, and low battery.
- Define precise location retention and automated deletion rules.
- Add an incident workflow and export suitable for emergency responders.
- Run field trials in low-connectivity areas and publish an offline emergency procedure.
