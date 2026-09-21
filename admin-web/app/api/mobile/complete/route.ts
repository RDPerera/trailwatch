import { NextRequest, NextResponse } from "next/server";
import { authenticateTrip, completeTrip } from "@/lib/trail-db";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json(); const tripId = String(body.tripId ?? ""); const token = String(body.token ?? "");
    if (!await authenticateTrip(tripId, token)) return NextResponse.json({ error: "Invalid trip credentials" }, { status: 401 });
    await completeTrip(tripId); return NextResponse.json({ completed: true });
  } catch (error) { console.error(error); return NextResponse.json({ error: "Trip could not be completed" }, { status: 500 }); }
}
