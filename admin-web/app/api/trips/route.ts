import { NextRequest, NextResponse } from "next/server";
import { createTrip, listTrips } from "@/lib/trail-db";

export const dynamic = "force-dynamic";

export async function GET() {
  try { return NextResponse.json({ trips: await listTrips() }); }
  catch (error) { console.error(error); return NextResponse.json({ error: "Trips are temporarily unavailable" }, { status: 503 }); }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const visitorName = String(body.visitorName ?? "").trim();
    const routeName = String(body.routeName ?? "").trim();
    const expectedMinutes = Number(body.expectedMinutes);
    const emergencyPhone = String(body.emergencyPhone ?? "").trim();
    if (!visitorName || !routeName || !Number.isFinite(expectedMinutes) || expectedMinutes < 15 || expectedMinutes > 1440) {
      return NextResponse.json({ error: "Enter a visitor, route, and trip duration between 15 minutes and 24 hours" }, { status: 400 });
    }
    return NextResponse.json({ trip: await createTrip({ visitorName, routeName, expectedMinutes, emergencyPhone }) }, { status: 201 });
  } catch (error) { console.error(error); return NextResponse.json({ error: "Could not issue the ticket" }, { status: 500 }); }
}
