import Link from "next/link";
import { requireProfile } from "@/lib/auth/profile";
import { navigationForProfile } from "@/lib/staff/navigation";

export default async function StaffOverviewPage() {
  const profile = await requireProfile("/staff");
  const workspaces = navigationForProfile(profile).filter((item) => item.href !== "/staff");
  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />STAFF WORKSPACE</p>
      <h1>Operations overview</h1>
      <p className="page-intro">
        Signed in with {profile.app_role === "admin" ? "administrator" : `${profile.staff_role} staff`} access. Choose an authorised workspace below.
      </p>
      <div className="staff-workspace-grid">
        {workspaces.map((workspace, index) => (
          <Link className="staff-workspace-card" href={workspace.href} key={workspace.href}>
            <span>{String(index + 1).padStart(2, "0")}</span>
            <h2>{workspace.label}</h2>
            <p>{workspace.description}</p>
          </Link>
        ))}
      </div>
    </section>
  );
}

