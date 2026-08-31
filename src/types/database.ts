export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          full_name: string | null;
          phone: string | null;
          birthday: string | null;
          locality: string | null;
          profession: string | null;
          industry: string | null;
          interests: string[] | null;
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
          phone?: string | null;
          birthday?: string | null;
          locality?: string | null;
          profession?: string | null;
          industry?: string | null;
          interests?: string[] | null;
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
      get_active_member_benefits: {
        Args: Record<string, never>;
        Returns: {
          category: string;
          benefit_title: string;
          partner_name: string;
          location: string;
          benefit_description: string;
          redemption_instructions: string;
          terms: string;
        }[];
      };
      get_member_events: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          title: string;
          description: string;
          venue: string;
          starts_at: string;
          booking_closes_at: string;
          refund_cutoff_at: string;
          capacity: number;
          price_paise: number;
          max_guests_per_member: number;
          pricing_model: "fixed_booking" | "per_attendee" | string;
          seats_available: number;
        }[];
      };
      create_event_booking: {
        Args: { p_event_id: string; p_guest_names?: string[] };
        Returns: string;
      };
      get_my_event_bookings: {
        Args: Record<string, never>;
        Returns: {
          booking_id: string;
          event_id: string;
          title: string;
          venue: string;
          starts_at: string;
          guest_names: string[];
          seats: number;
          status: "pending_payment" | "confirmed" | "cancelled" | string;
          amount_paise: number;
          payment_status: "pending" | "paid" | "refunded" | string;
          reservation_expires_at: string;
          can_cancel: boolean;
          refund_eligible: boolean;
        }[];
      };
      cancel_event_booking: {
        Args: { p_booking_id: string };
        Returns: string;
      };
      expire_my_event_reservations: {
        Args: Record<string, never>;
        Returns: number | boolean | void;
      };
      submit_member_support_request: {
        Args: { p_category: string; p_message: string };
        Returns: string;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
export type MemberBenefit = Database["public"]["Functions"]["get_active_member_benefits"]["Returns"][number];
export type MemberEvent = Database["public"]["Functions"]["get_member_events"]["Returns"][number];
export type MyEventBooking = Database["public"]["Functions"]["get_my_event_bookings"]["Returns"][number];
