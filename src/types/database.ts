export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

/**
 * Temporary database boundary for the migration scaffold.
 * Replace this with generated Supabase types before migrating data-heavy pages.
 */
export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          full_name: string | null;
          app_role: "member" | "staff" | "admin";
          staff_role: "general" | "marketing" | "technical" | null;
          membership_state: "active" | "payment_pending" | "suspended" | "expired" | "cancelled";
          member_number: string | null;
          founding_member_sequence: number | null;
          payment_offer_expires_at: string | null;
        };
        Insert: {
          id: string;
          full_name?: string | null;
          app_role?: "member" | "staff" | "admin";
          staff_role?: "general" | "marketing" | "technical" | null;
          membership_state?: "active" | "payment_pending" | "suspended" | "expired" | "cancelled";
          member_number?: string | null;
          founding_member_sequence?: number | null;
          payment_offer_expires_at?: string | null;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      validate_membership_invitation: {
        Args: { p_token: string };
        Returns: { email: string; expires_at: string; status: string }[];
      };
      accept_membership_invitation: {
        Args: { p_token: string };
        Returns: string;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
