import type { Metadata } from "next";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { MemberCard } from "@/components/member/member-card";
import { requireProfile } from "@/lib/auth/profile";

export const metadata: Metadata = {
  title: "Member Portal",
  description: "Private One Club member portal and membership card.",
  robots: { index: false, follow: false },
};

export default async function MemberPortalPage() {
  const profile = await requireProfile("/portal");
  const isActive = profile.membership_state === "active";
  const isPaymentPending = profile.membership_state === "payment_pending";
  const isSuspended = profile.membership_state === "suspended";

  return (
    <div className="section-shell">
      {/* Member Profile Overview Strip */}
      <section className="section portal-shell">
        <p className="eyebrow">
          <span />
          ONE CLUB PORTAL
        </p>

        <section className="portal-profile">
          <div>
            <small>Signed in as</small>
            <h1>{profile.full_name || "Member"}</h1>
            <p>{profile.membership_state === "active" ? "Active One Club Membership" : "Membership Status"}</p>
          </div>
          <div className="portal-facts">
            <span>
              <small>Role</small>
              <strong>{profile.app_role}</strong>
            </span>
            <span>
              <small>Membership</small>
              <strong className={isActive ? "state-active" : isSuspended ? "state-suspended" : ""}>
                {profile.membership_state.replace("_", " ")}
              </strong>
            </span>
            <span>
              <small>Member ID</small>
              <strong>{profile.member_number || "Pending"}</strong>
            </span>
          </div>
        </section>

        {/* State-specific views */}
        {isActive && (
          <section className="portal-view member-view">
            <div className="member-dashboard">
              <MemberCard profile={profile} />
              <div>
                <h2>Your membership is active</h2>
                <p>
                  Use your digital member card when redeeming privileges with One Club partners, or reserve experiences and properties in advance.
                </p>
                <div className="portal-actions">
                  <Button href="/portal/benefits" variant="primary">
                    Explore member benefits
                  </Button>
                  <Button href="/portal/events" variant="secondary">
                    View upcoming events
                  </Button>
                  <Button href="/portal/profile" variant="secondary">
                    Edit my profile
                  </Button>
                </div>
              </div>
            </div>
          </section>
        )}

        {isPaymentPending && (
          <section className="portal-view">
            <h2>Membership payment pending</h2>
            <p>
              Your Founding Membership invitation offer has been approved. Complete your ₹50,000 membership fee to activate your lifetime membership benefits.
              {profile.payment_offer_expires_at && (
                <> Offer valid until <strong>{new Date(profile.payment_offer_expires_at).toLocaleDateString()}</strong>.</>
              )}
            </p>
            <div className="portal-actions">
              <Button href="/portal/support?category=payment" variant="primary">
                Contact membership desk
              </Button>
              <Button href="/portal/profile" variant="secondary">
                Edit my profile
              </Button>
            </div>
          </section>
        )}

        {isSuspended && (
          <section className="portal-view">
            <h2>Membership access restricted</h2>
            <p>
              Your membership access is currently suspended. Digital member cards and partner privileges are unavailable. Please contact Member Support for assistance.
            </p>
            <div className="portal-actions">
              <Button href="/portal/support?category=membership_access" variant="primary">
                Contact Member Support
              </Button>
            </div>
          </section>
        )}

        {/* Member Shortcuts Grid */}
        {isActive && (
          <section className="member-shortcuts">
            <p className="eyebrow">
              <span />
              MEMBER ACCESS
            </p>
            <div className="card-grid four" style={{ marginTop: "24px" }}>
              <Link className="info-card" href="/portal/benefits">
                <span className="eyebrow compact">01</span>
                <h3>Privileges</h3>
                <p>Browse private partner offers and redemption details.</p>
              </Link>
              <Link className="info-card" href="/portal/events">
                <span className="eyebrow compact">02</span>
                <h3>Experiences</h3>
                <p>View upcoming events, live availability and your bookings.</p>
              </Link>
              <Link className="info-card" href="/portal/profile">
                <span className="eyebrow compact">03</span>
                <h3>My profile</h3>
                <p>Keep your personal details, profession and interests current.</p>
              </Link>
              <Link className="info-card" href="/portal/support">
                <span className="eyebrow compact">04</span>
                <h3>Support</h3>
                <p>Private concierge assistance for any membership request.</p>
              </Link>
            </div>
          </section>
        )}

        {/* Concierge / Support Card */}
        <aside className="portal-support-card">
          <div>
            <p className="eyebrow compact">MEMBER CONCIERGE</p>
            <h2>Need assistance?</h2>
            <p>
              Contact the One Club team for help with partner reservations, event bookings, guest privileges, or profile details.
            </p>
          </div>
          <Button href="/portal/support" variant="secondary">
            Contact One Club
          </Button>
        </aside>
      </section>
    </div>
  );
}

