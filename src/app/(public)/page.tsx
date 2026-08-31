import type { Metadata } from "next";
import Image from "next/image";
import { Button } from "@/components/ui/button";

export const metadata: Metadata = { title: "A New Kind of Connection", description: "A private lifestyle club for meaningful connections, curated experiences and exclusive member privileges." };

const gatherings = [
  ["icon-network.svg", "Business Meets", "Meet industry leaders, entrepreneurs and professionals in thoughtfully curated settings."],
  ["icon-coffee.svg", "Founder Breakfasts", "Smaller conversations designed for founders and decision-makers to exchange ideas."],
  ["icon-star.svg", "Themed Meets", "Curated gatherings around business, growth, lifestyle, interests and emerging ideas."],
  ["icon-calendar.svg", "Exclusive Events", "Members-only experiences designed to bring the community together."],
];

const categories = [
  ["icon-gym.svg", "Gyms", "Fitness centres and wellness spaces with exclusive member offers."],
  ["icon-hotel.svg", "Hotels & Resorts", "Handpicked stays and resorts at preferred member rates."],
  ["icon-adventure.svg", "Adventure Stays", "Unique escapes and memorable experiences in nature."],
  ["icon-spa.svg", "Spa & Salons", "Selected wellness, spa and grooming partners."],
  ["icon-car.svg", "Automotive", "Premium detailing and automotive lifestyle partners."],
];

export default function HomePage() {
  const legacyLogin = `${process.env.NEXT_PUBLIC_LEGACY_SITE_URL ?? "https://dev.oneclub.net.in"}/login.html`;
  return <>
    <section className="section home-hero">
      <div><p className="eyebrow"><span />A new kind of connection</p><h1>One Club.<br /><em>One life.</em><br />Unlimited possibilities.</h1><p className="hero-text">A private lifestyle club bringing together ambitious people, meaningful connections, curated experiences and exclusive privileges.</p><Button href="/contact" variant="primary">Request an Enquiry</Button><p className="micro-note">By invitation · Curated community</p></div>
      <div className="visual-frame"><Image src="/assets/hero.png" alt="One Club members connecting at an exclusive event" fill sizes="(max-width: 980px) 100vw, 50vw" priority /></div>
    </section>
    <section className="section"><div className="section-heading centered"><p className="eyebrow"><span />Connections that matter</p><h2>Meet people. <em>Open possibilities.</em></h2><p>One Club creates spaces where founders, business leaders and professionals can connect naturally, exchange ideas and build relationships that go beyond networking.</p></div><div className="card-grid four">{gatherings.map(([icon, title, copy]) => <article className="info-card" key={title}><Image src={`/assets/${icon}`} alt="" width={34} height={34} /><h3>{title}</h3><p>{copy}</p></article>)}</div></section>
    <section className="section membership-preview"><div className="membership-intro"><p className="eyebrow"><span />Founding membership</p><h2>For those shaping<br /><em>what comes next.</em></h2><p>One Club membership is offered by invitation. Approved applicants receive private access to the Founding Membership experience, member privileges and curated events.</p></div><article className="membership-card"><span className="membership-label">Invitation only</span><h3>One Club<br />Founding Member</h3><p>Lifetime recognition for the first 500 members of the One Club community.</p><div className="membership-meta"><span><small>Membership</small>Lifetime</span><span><small>Availability</small>First 500</span></div><Button href="/contact" variant="primary">Request an Enquiry</Button></article></section>
    <section className="section privilege"><div><p className="eyebrow"><span />The member experience</p><h2>Special care.<br /><em>Exclusive privileges.</em></h2><p>Membership extends beyond access. At our partner properties, members receive attentive service and preferential benefits designed to make every experience feel considered.</p><ul className="benefit-list"><li><span>01</span><div><strong>Personalised assistance</strong><small>A more attentive experience across selected partners.</small></div></li><li><span>02</span><div><strong>Priority access</strong><small>Early access and preferred booking opportunities where available.</small></div></li><li><span>03</span><div><strong>Exclusive discounts</strong><small>Member-only rates and offers at participating partners.</small></div></li><li><span>04</span><div><strong>Curated experiences</strong><small>Places and experiences selected for the community.</small></div></li></ul></div><div className="visual-frame privilege-frame"><Image src="/assets/benefits.png" alt="An exclusive partner experience" fill sizes="(max-width: 980px) 100vw, 50vw" /></div></section>
    <section className="section"><div className="section-heading centered"><p className="eyebrow"><span />Curated access</p><h2>A world of <em>possibilities.</em></h2><p>Explore a growing network of partner properties and experiences across wellness, hospitality, adventure and lifestyle.</p></div><div className="partner-grid">{categories.map(([icon, title, copy], index) => <article className="partner-card" key={title}><Image src={`/assets/${icon}`} alt="" width={30} height={30} /><span>{String(index + 1).padStart(2, "0")}</span><h3>{title}</h3><p>{copy}</p></article>)}</div></section>
    <section className="section event-preview"><div className="section-heading centered"><p className="eyebrow"><span />Upcoming experiences</p><h2>Gather with <em>purpose.</em></h2><p>Active members receive complete event details, live availability and secure booking access for themselves and eligible guests.</p></div><article className="event-card"><div><span className="event-date">Founding series · Bangalore</span><h3>Founder&apos;s Breakfast</h3><p>An intimate morning for founders and business leaders to exchange ideas over a curated breakfast.</p></div><span className="event-status">Members only</span></article></section>
    <section className="section home-contact"><div><p className="eyebrow"><span />Take the next step</p><h2>Interested in<br /><em>One Club?</em></h2><p>Tell us a little about yourself and our team will get in touch with more information about membership, upcoming events and partner privileges.</p></div><div className="cta-panel"><span>Invitation-led membership</span><h3>Let&apos;s start a conversation.</h3><p>Your enquiry is personally reviewed by the One Club team.</p><Button href="/contact" variant="primary">Request an Enquiry</Button></div></section>
    <section className="portal-preview"><p>Already a member? <a href={legacyLogin}>Sign in to access your account.</a></p></section>
  </>;
}

