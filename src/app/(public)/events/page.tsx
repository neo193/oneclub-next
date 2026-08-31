import type { Metadata } from "next";
import { ContentGrid, ContentPanel } from "@/components/public/content-panel";
import { PageHero } from "@/components/public/page-hero";

export const metadata: Metadata = { title: "Events", description: "Discover curated One Club events and member experiences." };
export default function EventsPage() { return <><PageHero eyebrow="Curated gatherings" title={<>Meet with <em>purpose.</em></>}><p>One Club brings members together through considered gatherings designed for conversation, discovery and shared experiences. Dates, venues, availability and booking terms are reserved for active members.</p></PageHero><ContentGrid><ContentPanel wide><span className="event-date">Founding series · Bangalore</span><h2>Founder&apos;s Breakfast</h2><p>An intimate, limited-seat morning for founders and business leaders to exchange ideas over a curated breakfast. Members receive complete attendance, guest, booking and cancellation details.</p></ContentPanel><ContentPanel><h3>Business Meets</h3><p>Thoughtful rooms for professional conversation and connection.</p></ContentPanel><ContentPanel><h3>Member Experiences</h3><p>Curated lifestyle, automotive, hospitality and adventure gatherings.</p></ContentPanel></ContentGrid></>; }

