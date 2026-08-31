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
          avatar_url: string | null;
          app_role: "member" | "staff" | "admin";
          staff_role: "general" | "marketing" | "technical" | null;
          membership_state: "none" | "active" | "payment_pending" | "suspended" | "expired" | "cancelled";
          member_number: string | null;
          founding_member_sequence: number | null;
          membership_plan: "founding_lifetime" | "annual" | null;
          membership_started_at: string | null;
          membership_expires_at: string | null;
          pending_membership_plan: "founding_lifetime" | "annual" | null;
          pending_membership_source: "razorpay" | "complimentary" | "offline" | "legacy" | null;
          membership_status_context: string | null;
          payment_offer_expires_at: string | null;
          created_at: string;
          updated_at: string;
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
          avatar_url?: string | null;
          app_role?: "member" | "staff" | "admin";
          staff_role?: "general" | "marketing" | "technical" | null;
          membership_state?: "none" | "active" | "payment_pending" | "suspended" | "expired" | "cancelled";
          member_number?: string | null;
          founding_member_sequence?: number | null;
          membership_plan?: "founding_lifetime" | "annual" | null;
          membership_started_at?: string | null;
          membership_expires_at?: string | null;
          pending_membership_plan?: "founding_lifetime" | "annual" | null;
          pending_membership_source?: "razorpay" | "complimentary" | "offline" | "legacy" | null;
          membership_status_context?: string | null;
          payment_offer_expires_at?: string | null;
          created_at?: string;
          updated_at?: string;
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
          pricing_model: "fixed_booking" | "per_person";
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
          payment_status: "unpaid" | "paid" | "refund_pending" | "refunded" | "not_required";
          booking_source: "member_payment" | "complimentary";
          reservation_expires_at: string | null;
          cancelled_at: string | null;
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
      list_enquiries_for_staff: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          full_name: string;
          email: string;
          phone: string;
          status: "new" | "contacted" | "approved" | "rejected" | "archived";
          created_at: string | null;
        }[];
      };
      approve_enquiry_and_create_invitation: {
        Args: { p_enquiry_id: string };
        Returns: string;
      };
      list_support_requests_for_staff: {
        Args: { p_status?: string | null };
        Returns: {
          id: string;
          category: string;
          message: string;
          status: "open" | "in_progress" | "resolved" | "closed";
          full_name: string | null;
          email: string;
          member_number: string | null;
          membership_state: string;
          created_at: string | null;
        }[];
      };
      update_support_request_status: {
        Args: { p_request_id: string; p_status: string };
        Returns: void;
      };
      get_technical_diagnostics: {
        Args: Record<string, never>;
        Returns: Json;
      };
      get_pending_refund_count: {
        Args: Record<string, never>;
        Returns: number;
      };
      list_refunds_for_admin: {
        Args: Record<string, never>;
        Returns: {
          booking_id: string;
          event_title: string;
          member_name: string | null;
          member_email: string;
          member_number: string | null;
          amount_paise: number;
          cancelled_at: string | null;
          payment_status: string;
          razorpay_payment_id: string;
          razorpay_refund_id: string | null;
          refund_status: "requested" | "processing" | "processed" | "failed";
          refund_source: string | null;
          refund_updated_at: string | null;
        }[];
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
export type StaffEnquiry = Database["public"]["Functions"]["list_enquiries_for_staff"]["Returns"][number];
export type StaffSupportRequest = Database["public"]["Functions"]["list_support_requests_for_staff"]["Returns"][number];
export type AdminRefund = Database["public"]["Functions"]["list_refunds_for_admin"]["Returns"][number];
