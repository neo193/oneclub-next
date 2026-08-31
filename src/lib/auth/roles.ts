export const appRoles = ["public", "member", "staff", "admin"] as const;

export type AppRole = (typeof appRoles)[number];

export const roleHome: Record<Exclude<AppRole, "public">, string> = {
  member: "/portal",
  staff: "/staff",
  admin: "/staff",
};

