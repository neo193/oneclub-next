import type { Metadata } from "next";
import { ContentGrid, ContentPanel } from "@/components/public/content-panel";
import { PageHero } from "@/components/public/page-hero";

export const metadata: Metadata = { title: "About", description: "Learn about One Club, Bangalore's invitation-led premium lifestyle community." };
export default function AboutPage() { return <><PageHero eyebrow="About One Club" title={<>Connections with <em>meaning.</em></>}><p>One Club is an invitation-led premium lifestyle community bringing together founders, investors, business leaders and professionals across Bangalore.</p></PageHero><ContentGrid><ContentPanel><h2>Our purpose</h2><p>Create trusted settings where ambitious people can build genuine relationships, exchange ideas and enjoy thoughtfully curated experiences.</p></ContentPanel><ContentPanel><h2>The member experience</h2><p>Membership combines curated gatherings with preferred care, privileges and offers across a growing network of lifestyle partners.</p></ContentPanel><ContentPanel><h2>Community</h2><p>A considered network of people who value access, contribution, discretion and meaningful conversation.</p></ContentPanel><ContentPanel><h2>Bangalore first</h2><p>One Club begins in Bangalore, with selected experiences across Karnataka and a vision to grow thoughtfully into new destinations.</p></ContentPanel></ContentGrid></>; }

