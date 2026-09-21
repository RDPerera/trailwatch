import { NextRequest, NextResponse } from "next/server";
import { joinTrip } from "@/lib/trail-db";

export async function POST(request: NextRequest) {
  try {
    const { code } = await request.json();
    const trip = await joinTrip(String(code ?? "").trim());
    if (!trip) return NextResponse.json({ error: "Ticket code not found" }, { status: 404 });
    if (trip.status === "completed") return NextResponse.json({ error: "This trip is already complete" }, { status: 409 });
    return NextResponse.json({ trip });
  } catch (error) { console.error(error); return NextResponse.json({ error: "Could not join this trip" }, { status: 500 }); }
}
