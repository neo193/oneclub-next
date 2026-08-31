import type { Metadata } from "next";
import { AuthShell } from "@/components/auth/auth-shell";
import { RecoveryForm } from "@/components/auth/recovery-form";

export const metadata:Metadata={title:"Recover Account",robots:{index:false,follow:false}};
export default async function ForgotPasswordPage({searchParams}:{searchParams:Promise<{error?:string}>}){const params=await searchParams;return <AuthShell eyebrow="Account recovery" title={<>Restore<br/><em>your access.</em></>} description="Enter the email address connected to your One Club account. We will send a time-limited recovery link." returnHref="/login" returnLabel="Return to sign in"><RecoveryForm initialMessage={params.error}/></AuthShell>;}
