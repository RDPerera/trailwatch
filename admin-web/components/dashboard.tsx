"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AlertTriangle, BatteryMedium, Check, Clock3, Compass, Copy, Download, Plus, Radio, RefreshCw, Search, Ticket, Users } from "lucide-react";
import QRCode from "qrcode";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import LiveMap from "@/components/live-map";

type Trip = {
  id: string; code: string; visitorName: string; emergencyPhone: string | null; routeName: string;
  expectedReturnAt: string; startedAt: string; completedAt: string | null; status: string;
  latitude: number | null; longitude: number | null; accuracyMeters: number | null;
  batteryPercent: number | null; recordedAt: string | null; alertKind: string | null;
};
type IssuedTrip = { id: string; code: string; accessToken: string; visitorName: string; routeName: string; expectedReturnAt: string };

const makeDemoTrips = (now: number): Trip[] => [
  { id:"demo-1",code:"TW-1048",visitorName:"Anika N.",emergencyPhone:null,routeName:"Cloud Forest Loop",expectedReturnAt:new Date(now+75*60000).toISOString(),startedAt:new Date(now-50*60000).toISOString(),completedAt:null,status:"active",latitude:6.8096,longitude:80.8027,accuracyMeters:11,batteryPercent:82,recordedAt:new Date(now-30000).toISOString(),alertKind:null },
  { id:"demo-2",code:"TW-1046",visitorName:"Ravi M.",emergencyPhone:null,routeName:"Ridge View Trail",expectedReturnAt:new Date(now+30*60000).toISOString(),startedAt:new Date(now-95*60000).toISOString(),completedAt:null,status:"active",latitude:6.8111,longitude:80.806,accuracyMeters:24,batteryPercent:31,recordedAt:new Date(now-7*60000).toISOString(),alertKind:null },
  { id:"demo-3",code:"TW-1041",visitorName:"Lena S.",emergencyPhone:null,routeName:"Bamboo Falls",expectedReturnAt:new Date(now-24*60000).toISOString(),startedAt:new Date(now-170*60000).toISOString(),completedAt:null,status:"active",latitude:6.8047,longitude:80.809,accuracyMeters:16,batteryPercent:68,recordedAt:new Date(now-60000).toISOString(),alertKind:null },
  { id:"demo-4",code:"TW-1039",visitorName:"Jon P.",emergencyPhone:null,routeName:"Cloud Forest Loop",expectedReturnAt:new Date(now+110*60000).toISOString(),startedAt:new Date(now-35*60000).toISOString(),completedAt:null,status:"active",latitude:6.8077,longitude:80.804,accuracyMeters:9,batteryPercent:74,recordedAt:new Date(now-2*60000).toISOString(),alertKind:null },
];

const relativeTime = (value: string | null, now: number) => {
  if (!value) return "No location yet";
  const seconds = Math.max(0, Math.round((now - new Date(value).getTime()) / 1000));
  if (seconds < 60) return `${seconds} sec ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  return `${Math.floor(minutes / 60)} hr ago`;
};
const initials = (name: string) => name.split(/\s+/).map((part) => part[0]).join("").slice(0, 2).toUpperCase();
const stateFor = (trip: Trip, now: number) => {
  if (trip.alertKind === "sos" || trip.status === "sos") return { label:"SOS", tone:"danger" };
  if (new Date(trip.expectedReturnAt).getTime() < now && trip.status === "active") return { label:"Overdue", tone:"danger" };
  if (!trip.recordedAt || now - new Date(trip.recordedAt).getTime() > 5 * 60000) return { label:"Signal stale", tone:"watch" };
  if (trip.status === "completed") return { label:"Returned", tone:"complete" };
  return { label:"On trail", tone:"safe" };
};

function Stat({ icon: Icon, value, label, tone = "default" }: { icon: typeof Users; value: number; label: string; tone?: string }) {
  return <div className={`stat-card ${tone === "danger" ? "stat-danger" : ""}`}><span className="stat-icon"><Icon aria-hidden="true" /></span><div><strong>{value}</strong><span>{label}</span></div></div>;
}

function TicketQr({ trip }: { trip: IssuedTrip }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (!canvasRef.current) return;
    void QRCode.toCanvas(canvasRef.current, trip.code, {
      width: 208,
      margin: 1,
      errorCorrectionLevel: "M",
      color: { dark: "#173f2c", light: "#ffffff" },
    });
  }, [trip.code]);

  function downloadQr() {
    const dataUrl = canvasRef.current?.toDataURL("image/png");
    if (!dataUrl) return;
    const link = document.createElement("a");
    link.download = `${trip.code}-qr.png`;
    link.href = dataUrl;
    link.click();
  }

  return <div className="ticket-ready"><span>Scan with the TrailWatch app</span><canvas ref={canvasRef} aria-label={`QR code for trip ${trip.code}`} /><strong>{trip.code}</strong><p>{trip.visitorName} · {trip.routeName}<br/>Expected back {new Date(trip.expectedReturnAt).toLocaleTimeString([], {hour:"2-digit",minute:"2-digit"})}</p><Button type="button" variant="outline" size="sm" onClick={downloadQr}><Download/> Download QR</Button></div>;
}

export default function Dashboard({ initialNow }: { initialNow: number }) {
  const [trips, setTrips] = useState<Trip[]>(() => makeDemoTrips(initialNow));
  const [demoMode, setDemoMode] = useState(true);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [issued, setIssued] = useState<IssuedTrip | null>(null);
  const [formError, setFormError] = useState("");
  const [copied, setCopied] = useState(false);
  const [now, setNow] = useState(initialNow);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch("/api/trips", { cache:"no-store" });
      if (!response.ok) throw new Error();
      const data = await response.json();
      if (data.trips.length) { setTrips(data.trips); setDemoMode(false); }
    } catch { setDemoMode(true); }
    finally { setLoading(false); setNow(Date.now()); }
  }, []);
  useEffect(() => { const first = window.setTimeout(refresh, 0); const timer = window.setInterval(refresh, 15000); return () => { window.clearTimeout(first); window.clearInterval(timer); }; }, [refresh]);

  useEffect(() => {
    const context = (document as Document & { modelContext?: { registerTool: (tool: unknown, options?: { signal?: AbortSignal }) => void | Promise<void> } }).modelContext;
    if (!context?.registerTool) return;
    const lifecycle = new AbortController();
    void Promise.resolve(context.registerTool({ name:"refresh_trailwatch_dashboard", title:"Refresh trail dashboard", description:"Refresh the live trip list and visitor locations shown on the TrailWatch dashboard.", inputSchema:{ type:"object",properties:{},additionalProperties:false }, annotations:{ readOnlyHint:true,untrustedContentHint:false }, execute:async()=>{ await refresh(); return { refreshed:true }; } }, { signal:lifecycle.signal })).catch(console.error);
    void Promise.resolve(context.registerTool({ name:"start_ticket_creation", title:"Start ticket creation", description:"Open the TrailWatch ticket form so a ranger can enter and review a new visitor trip.", inputSchema:{ type:"object",properties:{},additionalProperties:false }, annotations:{ readOnlyHint:false,untrustedContentHint:false }, execute:()=>{ setDialogOpen(true); return { opened:true }; } }, { signal:lifecycle.signal })).catch(console.error);
    return () => lifecycle.abort();
  }, [refresh]);

  const visible = useMemo(() => trips.filter((trip) => `${trip.visitorName} ${trip.code} ${trip.routeName}`.toLowerCase().includes(query.toLowerCase())), [trips, query]);
  const active = trips.filter((trip) => trip.status !== "completed");
  const alerts = active.filter((trip) => stateFor(trip, now).tone !== "safe");
  const returningSoon = active.filter((trip) => { const remaining = new Date(trip.expectedReturnAt).getTime() - now; return remaining > 0 && remaining < 45 * 60000; });

  async function createTicket(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setFormError(""); const data = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/trips", { method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({visitorName:data.get("visitorName"),emergencyPhone:data.get("emergencyPhone"),routeName:data.get("routeName"),expectedMinutes:Number(data.get("expectedMinutes"))}) });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Could not issue ticket");
      setIssued(body.trip); setDemoMode(false); await refresh();
    } catch (error) { setFormError(error instanceof Error ? error.message : "Could not issue ticket"); }
  }
  async function copyTicket() {
    if (!issued) return;
    await navigator.clipboard.writeText(`TrailWatch ticket ${issued.code}\nRoute: ${issued.routeName}\nExpected return: ${new Date(issued.expectedReturnAt).toLocaleString()}`);
    setCopied(true); setTimeout(()=>setCopied(false),1800);
  }

  const today = new Intl.DateTimeFormat("en", { weekday:"long",day:"numeric",month:"long",timeZone:"Asia/Colombo" }).format(new Date());
  return <main className="app-shell">
    <header className="topbar"><div className="brand"><span className="brand-mark"><Compass /></span><div><strong>TrailWatch</strong><span>Park safety desk</span></div></div><div className="top-actions"><span className="sync"><i /> {loading ? "Syncing…" : "Live"}{demoMode ? " · demo data" : " · just now"}</span><Dialog open={dialogOpen} onOpenChange={(open)=>{setDialogOpen(open);if(!open)setIssued(null)}}><DialogTrigger asChild><Button><Plus /> Issue ticket</Button></DialogTrigger><DialogContent><DialogHeader><DialogTitle>{issued ? "Ticket ready" : "Issue trail ticket"}</DialogTitle><DialogDescription>{issued ? "Ask the visitor to scan this QR code with the TrailWatch app." : "Record the visitor and their expected return before they leave the counter."}</DialogDescription></DialogHeader>{issued ? <TicketQr trip={issued}/> : <form id="ticket-form" className="ticket-form" onSubmit={createTicket}><Label htmlFor="visitorName">Visitor name</Label><Input id="visitorName" name="visitorName" required placeholder="e.g. Nimal Perera"/><Label htmlFor="emergencyPhone">Emergency contact</Label><Input id="emergencyPhone" name="emergencyPhone" inputMode="tel" placeholder="Optional phone number"/><Label htmlFor="routeName">Trail</Label><Input id="routeName" name="routeName" required defaultValue="Cloud Forest Loop"/><Label htmlFor="expectedMinutes">Expected duration (minutes)</Label><Input id="expectedMinutes" name="expectedMinutes" required type="number" min="15" max="1440" defaultValue="120"/>{formError && <p className="form-error">{formError}</p>}</form>}<DialogFooter>{issued ? <><Button variant="outline" onClick={copyTicket}>{copied?<Check/>:<Copy/>}{copied?"Copied":"Copy details"}</Button><Button onClick={()=>{setDialogOpen(false);setIssued(null)}}>Done</Button></> : <Button type="submit" form="ticket-form"><Ticket /> Issue ticket</Button>}</DialogFooter></DialogContent></Dialog><span className="avatar">DP</span></div></header>
    <section className="dashboard-heading"><div><p>{today}</p><h1>Trail operations</h1></div><div className="search-wrap"><Search /><Input value={query} onChange={(event)=>setQuery(event.target.value)} aria-label="Search visitors or tickets" placeholder="Search visitor or ticket" /></div></section>
    <section className="stats" aria-label="Today’s trip summary"><Stat icon={Users} value={active.length} label="Active visitors"/><Stat icon={Ticket} value={trips.length} label="Tickets today"/><Stat icon={Clock3} value={returningSoon.length} label="Returning soon"/><Stat icon={AlertTriangle} value={alerts.length} label="Needs attention" tone="danger"/></section>
    <section className="workspace"><div className="map-panel"><div className="panel-title"><div><h2>Live trail map</h2><p>Drag to move · scroll or pinch to zoom</p></div><button className="map-action" onClick={refresh}><RefreshCw className={loading?"spin":""}/> Refresh</button></div><LiveMap trips={active} now={now}/></div>
      <aside className="alerts-panel"><div className="panel-title"><div><h2>Attention</h2><p>Review the most urgent trip first</p></div><span className="count">{alerts.length}</span></div>{alerts.length ? alerts.slice(0,3).map((trip)=>{const state=stateFor(trip, now);return <article className={`alert-card ${state.tone==="danger"?"urgent":""}`} key={trip.id}><span className={`alert-icon ${state.tone==="watch"?"amber":""}`}>{state.tone==="danger"?<AlertTriangle/>:<Radio/>}</span><div><span className={`eyebrow ${state.tone==="watch"?"amber-text":""}`}>{state.label}</span><h3>{trip.visitorName}</h3><p>{trip.routeName} · {trip.code}<br/>{relativeTime(trip.recordedAt, now)}</p></div></article>}) : <div className="empty-alerts"><Check/><strong>No active alerts</strong><span>All reporting visitors are within their expected trip window.</span></div>}<div className="response-note"><strong>Location is an aid, not a guarantee.</strong><span>Follow the park emergency procedure before dispatching a response.</span></div></aside></section>
    <section className="visitor-panel"><div className="panel-title"><div><h2>Visitors</h2><p>{visible.length} matching trips</p></div><button className="text-button" onClick={refresh}>Refresh list</button></div><div className="visitor-table"><div className="visitor-row table-head"><span>Visitor</span><span>Route</span><span>Last update</span><span>Battery</span><span>Status</span></div>{visible.length ? visible.map((trip)=>{const state=stateFor(trip, now);return <div className="visitor-row" key={trip.id}><span className="visitor-name"><i>{initials(trip.visitorName)}</i><span><strong>{trip.visitorName}</strong><small>{trip.code}</small></span></span><span>{trip.routeName}</span><span>{relativeTime(trip.recordedAt, now)}</span><span className="battery"><BatteryMedium/>{trip.batteryPercent==null?"—":`${trip.batteryPercent}%`}</span><span><em className={`status ${state.tone}`}>{state.label}</em></span></div>}) : <div className="table-empty">No trips match this search.</div>}</div></section>
  </main>;
}
