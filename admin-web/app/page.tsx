import Dashboard from "@/components/dashboard";

export const dynamic = "force-dynamic";

export default function Home() {
  // The server timestamp is passed to the client component to keep demo data stable during hydration.
  // eslint-disable-next-line react-hooks/purity
  return <Dashboard initialNow={Date.now()} />;
}
