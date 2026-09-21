"use client";

import { LocateFixed, Navigation, Users } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Circle, FeatureGroup, LayerGroup, Map as LeafletMap, Marker } from "leaflet";

type MapTrip = {
  id: string;
  code: string;
  visitorName: string;
  routeName: string;
  status: string;
  alertKind: string | null;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  batteryPercent: number | null;
  recordedAt: string | null;
  expectedReturnAt: string;
};

function markerTone(trip: MapTrip, now: number) {
  if (trip.alertKind === "sos" || trip.status === "sos") return "danger";
  if (new Date(trip.expectedReturnAt).getTime() < now) return "danger";
  if (!trip.recordedAt || now - new Date(trip.recordedAt).getTime() > 5 * 60_000) return "watch";
  return "safe";
}

function formatUpdate(value: string | null, now: number) {
  if (!value) return "No GPS update yet";
  const minutes = Math.max(0, Math.floor((now - new Date(value).getTime()) / 60_000));
  return minutes < 1 ? "Updated just now" : `Updated ${minutes} min ago`;
}

const MENDIS_PARK_CENTER: [number, number] = [6.6807756, 79.9257330];

function offsetPoint(center: [number, number], eastMeters: number, northMeters: number): [number, number] {
  const latitude = center[0] + northMeters / 111_320;
  const longitude = center[1] + eastMeters / (111_320 * Math.cos(center[0] * Math.PI / 180));
  return [latitude, longitude];
}

function createMockPark(L: typeof import("leaflet"), map: LeafletMap, center: [number, number]) {
  const group = L.featureGroup().addTo(map);
  const boundary = [
    offsetPoint(center, -1_050, -620),
    offsetPoint(center, -1_180, 120),
    offsetPoint(center, -760, 900),
    offsetPoint(center, -80, 1_170),
    offsetPoint(center, 820, 940),
    offsetPoint(center, 1_180, 260),
    offsetPoint(center, 930, -720),
    offsetPoint(center, 160, -1_060),
  ];
  const boundaryShape = L.polygon(boundary, {
    color: "#1f6a43",
    weight: 4,
    dashArray: "10 7",
    fillColor: "#42a66d",
    fillOpacity: 0.12,
  }).addTo(group).bindPopup("<strong>Mendis Imagine Park</strong><br>Mock heritage zone · Mendis Weda Mawatha");

  const start = offsetPoint(center, -720, -560);
  const destination = offsetPoint(center, 690, 700);
  const route = [
    start,
    offsetPoint(center, -460, -350),
    offsetPoint(center, -210, -120),
    offsetPoint(center, 60, 10),
    offsetPoint(center, 230, 260),
    offsetPoint(center, 470, 430),
    destination,
  ];
  L.polyline(route, { color: "#ffffff", weight: 10, opacity: 0.9, lineCap: "round", lineJoin: "round" }).addTo(group);
  L.polyline(route, { color: "#f97316", weight: 6, opacity: 1, lineCap: "round", lineJoin: "round", dashArray: "1 0" })
    .addTo(group)
    .bindTooltip("A → B highlighted trail", { sticky: true });

  const startIcon = L.divIcon({ className: "park-icon-wrapper", html: '<span class="route-point start">A</span>', iconSize: [34, 34], iconAnchor: [17, 17] });
  const destinationIcon = L.divIcon({ className: "park-icon-wrapper", html: '<span class="route-point destination">B</span>', iconSize: [40, 40], iconAnchor: [20, 20] });
  L.marker(start, { icon: startIcon, zIndexOffset: 700 }).addTo(group).bindTooltip("A · Gate House", { permanent: true, direction: "bottom", className: "park-place-label", offset: [0, 12] });
  L.marker(destination, { icon: destinationIcon, zIndexOffset: 700 }).addTo(group).bindTooltip("B · Archive House", { permanent: true, direction: "top", className: "park-place-label", offset: [0, -14] });

  const places = [
    { name: "Clay House", point: offsetPoint(center, -460, -350), kind: "clay" },
    { name: "Mendis Manor", point: offsetPoint(center, -210, -120), kind: "manor" },
    { name: "Courtyard House", point: offsetPoint(center, 60, 10), kind: "courtyard" },
    { name: "Garden House", point: offsetPoint(center, 230, 260), kind: "garden" },
    { name: "Veranda House", point: offsetPoint(center, 470, 430), kind: "veranda" },
  ];
  for (const place of places) {
    const icon = L.divIcon({ className: "park-icon-wrapper", html: `<span class="park-place ${place.kind}"><i></i></span>`, iconSize: [24, 24], iconAnchor: [12, 12] });
    L.marker(place.point, { icon, zIndexOffset: 400 }).addTo(group).bindTooltip(place.name, { permanent: true, direction: "top", className: "park-place-label", offset: [0, -8] });
  }
  return { group, bounds: boundaryShape.getBounds() };
}

export default function LiveMap({ trips, now }: { trips: MapTrip[]; now: number }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const visitorsRef = useRef<LayerGroup | null>(null);
  const userMarkerRef = useRef<Marker | null>(null);
  const accuracyRef = useRef<Circle | null>(null);
  const parkRef = useRef<FeatureGroup | null>(null);
  const leafletRef = useRef<typeof import("leaflet") | null>(null);
  const fittedRef = useRef(false);
  const [ready, setReady] = useState(false);
  const [locating, setLocating] = useState(false);
  const [locationMessage, setLocationMessage] = useState("Finding your location…");

  const locateMe = useCallback(() => {
    const map = mapRef.current;
    const L = leafletRef.current;
    if (!map || !L || !navigator.geolocation) {
      setLocationMessage("Location is not available in this browser");
      return;
    }
    setLocating(true);
    setLocationMessage("Finding your location…");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const point: [number, number] = [position.coords.latitude, position.coords.longitude];
        if (userMarkerRef.current) userMarkerRef.current.setLatLng(point);
        else {
          const icon = L.divIcon({
            className: "map-marker-wrapper",
            html: '<span class="map-marker my-location"><span></span></span>',
            iconSize: [26, 26],
            iconAnchor: [13, 13],
          });
          userMarkerRef.current = L.marker(point, { icon, zIndexOffset: 1000 })
            .addTo(map)
            .bindTooltip("Your current location", { permanent: false, direction: "top" });
        }
        if (accuracyRef.current) accuracyRef.current.removeFrom(map);
        accuracyRef.current = L.circle(point, {
          radius: Math.max(position.coords.accuracy, 10),
          color: "#2563eb",
          fillColor: "#60a5fa",
          fillOpacity: 0.12,
          weight: 1,
        }).addTo(map);
        map.flyTo(point, Math.max(map.getZoom(), 16), { duration: 0.8 });
        setLocationMessage(`Your location · accurate to ${Math.round(position.coords.accuracy)} m`);
        setLocating(false);
      },
      (error) => {
        const message = error.code === error.PERMISSION_DENIED
          ? "Allow location access to show your position"
          : "Could not get your current location";
        setLocationMessage(message);
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 15_000, maximumAge: 10_000 },
    );
  }, []);

  useEffect(() => {
    let cancelled = false;
    void import("leaflet").then((L) => {
      if (cancelled || !containerRef.current || mapRef.current) return;
      leafletRef.current = L;
      const map = L.map(containerRef.current, {
        center: MENDIS_PARK_CENTER,
        zoom: 14,
        zoomControl: true,
        attributionControl: true,
      });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        maxZoom: 19,
      }).addTo(map);
      visitorsRef.current = L.layerGroup().addTo(map);
      const park = createMockPark(L, map, MENDIS_PARK_CENTER);
      parkRef.current = park.group;
      fittedRef.current = true;
      map.fitBounds(park.bounds, { padding: [30, 30], maxZoom: 15 });
      mapRef.current = map;
      setReady(true);
      window.setTimeout(() => map.invalidateSize(), 0);
    });
    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
      visitorsRef.current = null;
      parkRef.current = null;
      accuracyRef.current = null;
      leafletRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    const L = leafletRef.current;
    const layer = visitorsRef.current;
    if (!ready || !map || !L || !layer) return;
    layer.clearLayers();
    const locations: [number, number][] = [];
    for (const trip of trips) {
      if (typeof trip.latitude !== "number" || typeof trip.longitude !== "number") continue;
      const point: [number, number] = [trip.latitude, trip.longitude];
      locations.push(point);
      const tone = markerTone(trip, now);
      const icon = L.divIcon({
        className: "map-marker-wrapper",
        html: `<span class="map-marker visitor ${tone}"><span></span></span>`,
        iconSize: [30, 30],
        iconAnchor: [15, 15],
      });
      const popup = document.createElement("div");
      popup.className = "visitor-popup";
      const name = document.createElement("strong");
      name.textContent = trip.visitorName;
      const route = document.createElement("span");
      route.textContent = `${trip.routeName} · ${trip.code}`;
      const update = document.createElement("span");
      update.textContent = `${formatUpdate(trip.recordedAt, now)}${trip.batteryPercent == null ? "" : ` · Battery ${trip.batteryPercent}%`}`;
      popup.append(name, route, update);
      L.marker(point, { icon }).addTo(layer).bindPopup(popup);
      if (trip.accuracyMeters && trip.accuracyMeters > 10) {
        L.circle(point, { radius: trip.accuracyMeters, color: tone === "danger" ? "#b72c22" : "#29875a", weight: 1, fillOpacity: 0.06 }).addTo(layer);
      }
    }
    if (!fittedRef.current && locations.length) {
      fittedRef.current = true;
      if (locations.length === 1) map.setView(locations[0], 16);
      else map.fitBounds(L.latLngBounds(locations), { padding: [46, 46], maxZoom: 16 });
    }
  }, [now, ready, trips]);

  useEffect(() => {
    if (ready) locateMe();
  }, [locateMe, ready]);

  const visibleVisitors = trips.filter((trip) => typeof trip.latitude === "number" && typeof trip.longitude === "number").length;

  return <div className="live-map-shell">
    <div ref={containerRef} className="live-map" aria-label="Interactive map with visitor and ranger locations" />
    {!ready && <div className="map-loading">Loading interactive map…</div>}
    <div className="map-park-badge"><span>Mock heritage park</span><strong>Mendis Imagine Park</strong><small>Mendis Weda Mawatha · houses · A → B trail</small></div>
    <div className="map-legend" aria-label="Map legend">
      <span><i className="boundary"/>Park boundary</span>
      <span><i className="route"/>A → B trail</span>
      <span><i className="safe"/>Reporting</span>
      <span><i className="watch"/>Stale</span>
      <span><i className="danger"/>SOS / overdue</span>
    </div>
    <div className="map-location-card">
      <div><Navigation/><span><strong>{visibleVisitors} visitor locations</strong><small>{locationMessage}</small></span></div>
      <button type="button" onClick={locateMe} disabled={locating}><LocateFixed/>{locating ? "Locating…" : "My location"}</button>
    </div>
    {!visibleVisitors && <div className="map-empty"><Users/><span><strong>No visitor GPS yet</strong><small>Their markers appear after the mobile app sends a location.</small></span></div>}
  </div>;
}
