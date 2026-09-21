import { NextRequest, NextResponse } from "next/server";
import { authenticateTrip, raiseSos } from "@/lib/trail-db";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json(); const tripId = String(body.tripId ?? ""); const token = String(body.token ?? "");
    if (!await authenticateTrip(tripId, token)) return NextResponse.json({ error: "Invalid trip credentials" }, { status: 401 });
    await raiseSos(tripId, String(body.message ?? "Visitor requested emergency assistance").slice(0, 300));
    return NextResponse.json({ accepted: true });
  } catch (error) { console.error(error); return NextResponse.json({ error: "SOS could not be sent" }, { status: 500 }); }
}
