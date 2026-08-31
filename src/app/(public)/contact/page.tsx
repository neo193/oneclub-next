import type { Metadata } from "next";
import { EnquiryForm } from "@/components/public/enquiry-form";
import { PageHero } from "@/components/public/page-hero";

export const metadata: Metadata = { title: "Request an Enquiry", description: "Request an invitation enquiry from One Club." };
export default function ContactPage() { return <><PageHero eyebrow="Request an enquiry" title={<>Start a <em>conversation.</em></>}><p>Share your contact details. The One Club team will get in touch and may issue a private membership invitation after approval.</p></PageHero><section className="section contact-section"><div><h2>Invitation-led.<br /><em>Personally reviewed.</em></h2><p>Submitting an enquiry does not create a membership or provide access to purchase one.</p></div><EnquiryForm /></section></>; }

