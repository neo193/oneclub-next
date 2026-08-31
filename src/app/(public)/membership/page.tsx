import type { Metadata } from "next";
import { ContentGrid, ContentPanel } from "@/components/public/content-panel";
import { PageHero } from "@/components/public/page-hero";
import { Button } from "@/components/ui/button";

export const metadata: Metadata = { title: "Membership", description: "Explore the invitation-only One Club Founding Membership." };
export default function MembershipPage() { return <><PageHero eyebrow="Invitation only" title={<>One Club <em>Founding Member.</em></>}><p>Lifetime membership and special founding recognition for the first 500 approved members.</p></PageHero><ContentGrid><ContentPanel><h2>₹50,000</h2><p>A one-time Founding Membership fee for lifetime access. Any applicable taxes will be communicated before payment.</p></ContentPanel><ContentPanel><h2>Founding recognition</h2><p>A unique founding-member identity, special graphics and selected welcome benefits.</p></ContentPanel><ContentPanel><h2>Member privileges</h2><ul><li>Access to the complete partner and benefit catalogue</li><li>Preferential care and selected partner offers</li><li>Eligibility for curated member events</li><li>Personal member identifier</li></ul></ContentPanel><ContentPanel><h2>How to join</h2><p>Submit an enquiry. Once approved, the One Club team sends a private 30-day invitation link.</p><Button href="/contact" variant="primary">Request an Enquiry</Button></ContentPanel></ContentGrid></>; }

