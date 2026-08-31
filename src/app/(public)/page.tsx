import { Button } from "@/components/ui/button";

export default function HomePage() {
  return (
    <section className="hero section-shell">
      <p className="eyebrow">The next chapter</p>
      <h1>One Club, rebuilt for what comes next.</h1>
      <p className="lede">
        The production application is being migrated into a typed, component-based
        system while the existing member experience remains available.
      </p>
      <div className="button-row">
        <Button href="/membership" variant="primary">Explore membership</Button>
        <Button href="/portal">Member portal</Button>
      </div>
    </section>
  );
}

