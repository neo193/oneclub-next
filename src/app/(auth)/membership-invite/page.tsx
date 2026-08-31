import type { Metadata } from "next";
import { AuthShell } from "@/components/auth/auth-shell";
import { InvitationCard } from "@/components/auth/invitation-card";

export const metadata:Metadata={title:"Private Membership Invitation",robots:{index:false,follow:false}};
export default async function MembershipInvitePage({searchParams}:{searchParams:Promise<{token?:string}>}){const {token}=await searchParams;return <AuthShell eyebrow="Private invitation" title={<>Founding<br/><em>membership.</em></>} description="This private link is valid only for the approved email address and expires 30 days after generation." returnHref="/login" returnLabel="Member login"><InvitationCard token={token??null}/></AuthShell>;}
