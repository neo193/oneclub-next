import type { ReactNode } from "react";
import { PublicFooter } from "@/components/layout/public-footer";
import { PublicHeader } from "@/components/layout/public-header";

export function PublicShell({ children }: { children: ReactNode }) {
  return <><PublicHeader /><main>{children}</main><PublicFooter /></>;
}

