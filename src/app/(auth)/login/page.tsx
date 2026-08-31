import type { Metadata } from "next";
import { AuthShell } from "@/components/auth/auth-shell";
import { LoginForm } from "@/components/auth/login-form";
import { safeInternalPath } from "@/lib/auth/redirects";

export const metadata:Metadata={title:"Login",description:"Secure One Club member and staff login.",robots:{index:false,follow:false}};
export default async function LoginPage({searchParams}:{searchParams:Promise<{next?:string;error?:string;password?:string}>}){const params=await searchParams;const message=params.error??(params.password==="updated"?"Password updated. Sign in with your new password.":"");return <AuthShell eyebrow="Private access" title={<>Welcome<br/><em>back.</em></>} description="Sign in to continue to the appropriate member, staff or administrator portal."><LoginForm nextPath={safeInternalPath(params.next)} initialMessage={message}/></AuthShell>;}
