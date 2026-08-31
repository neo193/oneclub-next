import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthShell } from "@/components/auth/auth-shell";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";
import { createClient } from "@/lib/supabase/server";

export const metadata:Metadata={title:"Set New Password",robots:{index:false,follow:false}};
export default async function ResetPasswordPage(){const supabase=await createClient();const {data}=await supabase.auth.getClaims();if(!data?.claims)redirect("/forgot-password?error=Open%20a%20new%20recovery%20link%20to%20reset%20your%20password.");return <AuthShell eyebrow="Secure password reset" title={<>Choose a<br/><em>new password.</em></>} description="The recovery link verifies your account. Choose a unique password containing at least eight characters."><ResetPasswordForm/></AuthShell>;}
