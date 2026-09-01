import type { NextRequest } from "next/server";
import { refreshSession } from "@/lib/supabase/proxy";

export async function proxy(request: NextRequest) {
  return refreshSession(request);
}

export const config = {
  // Session refresh is only needed before protected server-rendered routes.
  // Running it for public and authentication pages makes those pages depend on
  // Supabase availability and previously introduced 25-second retry delays.
  matcher: ["/portal/:path*", "/staff/:path*"],
};
