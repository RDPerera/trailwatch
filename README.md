# TrailWatch

TrailWatch is an MVP safety and navigation platform for hiking trails and parks. Ticket-counter staff issue a trip code in the web dashboard. The Flutter app opens on a visitor map, scans the ticket QR code, and sends GPS and battery updates to the shared API while the trip is active.

## Project structure

- `admin-web/` — responsive ranger dashboard, API routes, and Cloudflare D1 schema
- `mobile/` — Flutter app for Android and iOS
- `docs/architecture.md` — system behavior and production considerations

## Run the admin dashboard locally

```bash
cd admin-web
npm run build
node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/0000_busy_shriek.sql
npm run dev
```

Open `http://localhost:5173`. The dashboard uses demonstration records if its database is unavailable or empty. Issue a ticket to start using real local records.

## Run the Flutter app

```bash
cd mobile
flutter pub get
flutter run
```

The mobile app uses `https://trailwatch.dilanp.duckdns.org` by default. A different backend can still be supplied with `--dart-define=TRAILWATCH_API_URL=https://example.com` or changed from the app's server settings.

## MVP behavior

- The mobile app opens on the mock Mendis Imagine Park map at Mendis Weda Mawatha.
- A highlighted standard route runs from Gate House (A) to Archive House (B).
- Visitors can search the fictional house artifacts and request a route from their location or between two artifacts.
- Staff issue a visitor ticket with route and expected duration.
- The dashboard generates a downloadable QR code for every ticket.
- The visitor scans the QR code in the app or enters the generated `TW-...` code.
- The app requests location permission and sends a GPS update every minute while open.
- Failed location updates are queued on the device and retried.
- The visitor can send an SOS or mark the trip safely completed.
- The dashboard refreshes every 15 seconds and highlights overdue, stale, and SOS trips.

## Important limitation

The artifact positions, park boundary, and walking lines are mock data for demonstration. Directions connect the defined artifact trail rather than using a turn-by-turn road-routing service. The MVP performs periodic tracking while the Flutter app is open. Reliable background tracking on locked phones requires the next phase: Android foreground-service setup, iOS background-location configuration, explicit always-on permission UX, and field testing for battery usage. The interface does not claim guaranteed rescue coverage.
