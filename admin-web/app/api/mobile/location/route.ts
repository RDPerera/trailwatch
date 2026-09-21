import { NextRequest, NextResponse } from "next/server";
import { addLocation, authenticateTrip } from "@/lib/trail-db";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const tripId = String(body.tripId ?? ""); const token = String(body.token ?? "");
    const latitude = Number(body.latitude); const longitude = Number(body.longitude);
    if (!tripId || !token || !Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return NextResponse.json({ error: "Invalid location update" }, { status: 400 });
    const trip = await authenticateTrip(tripId, token);
    if (!trip) return NextResponse.json({ error: "Invalid trip credentials" }, { status: 401 });
    if (trip.status === "completed") return NextResponse.json({ error: "Trip is complete" }, { status: 409 });
    await addLocation({ tripId, latitude, longitude, accuracyMeters: Number(body.accuracyMeters) || undefined, altitudeMeters: Number(body.altitudeMeters) || undefined, batteryPercent: Number(body.batteryPercent) || undefined, recordedAt: String(body.recordedAt ?? new Date().toISOString()) });
    return NextResponse.json({ accepted: true, receivedAt: new Date().toISOString() });
  } catch (error) { console.error(error); return NextResponse.json({ error: "Location could not be stored" }, { status: 500 }); }
}
