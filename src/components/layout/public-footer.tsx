import Link from "next/link";

export function PublicFooter() {
  return <footer className="site-footer"><span>© 2026 One Club</span><span>One Club · Oneclub.net.in</span><div><Link href="/privacy">Privacy Policy</Link><Link href="/terms">Terms & Conditions</Link></div></footer>;
}

