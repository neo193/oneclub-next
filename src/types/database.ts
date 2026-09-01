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
      get_active_member_benefit_catalogue: {
        Args: Record<string, never>;
        Returns: {
          category: string; benefit_title: string; partner_name: string; location: string;
          benefit_description: string; redemption_instructions: string; terms: string;
          locations: { id: string; name: string; address: string }[];
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
      list_members_for_management: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          full_name: string | null;
          email: string;
          member_number: string | null;
          membership_state: Profile["membership_state"];
        }[];
      };
      set_member_access_state: {
        Args: { p_member_id: string; p_action: "suspend" | "reactivate"; p_reason: string };
        Returns: void;
      };
      get_member_admin_record: { Args: { p_member_id: string }; Returns: Json };
      add_member_admin_note: { Args: { p_member_id: string; p_note: string }; Returns: string };
      export_members_for_management: { Args: Record<string, never>; Returns: Json };
      get_member_membership_control: { Args: { p_member_id: string }; Returns: Json };
      admin_update_member_profile: { Args: { p_member_id: string; p_full_name: string; p_phone: string; p_reason: string }; Returns: Json };
      admin_cancel_membership: { Args: { p_member_id: string; p_reason: string }; Returns: void };
      admin_revoke_pending_membership_offer: { Args: { p_member_id: string; p_reason: string }; Returns: void };
      admin_change_membership_expiry: { Args: { p_member_id: string; p_new_expiry: string; p_reason: string }; Returns: void };
      admin_grant_complimentary_membership: { Args: { p_member_id: string; p_plan: "founding_lifetime" | "annual"; p_reason: string }; Returns: void };
      admin_restore_cancelled_membership_offer: { Args: { p_member_id: string; p_reason: string }; Returns: Json };
      admin_restore_expired_membership_complimentary: { Args: { p_member_id: string; p_reason: string }; Returns: void };
      admin_reopen_expired_membership_for_payment: { Args: { p_member_id: string; p_reason: string }; Returns: Json };
      admin_record_offline_membership_payment: {
        Args: { p_member_id: string; p_plan: "founding_lifetime" | "annual"; p_amount_paise: number; p_payment_method: string; p_transaction_reference: string; p_payment_received_at: string; p_reason: string };
        Returns: void;
      };
      list_events_for_management: {
        Args: Record<string, never>;
        Returns: {
          id: string; title: string; description: string; venue: string; starts_at: string;
          booking_closes_at: string; refund_cutoff_at: string; capacity: number; price_paise: number;
          max_guests_per_member: number; pricing_model: "per_person" | "fixed_booking";
          status: "draft" | "published" | "cancelled" | "completed"; booked_seats: number; held_seats: number;
        }[];
      };
      save_event: {
        Args: { p_id: string | null; p_title: string; p_description: string; p_venue: string; p_starts_at: string; p_booking_closes_at: string; p_refund_cutoff_at: string; p_capacity: number; p_price_paise: number; p_max_guests_per_member: number; p_pricing_model: string; p_status: string; p_capacity_change_reason?: string | null };
        Returns: string;
      };
      check_event_deletion: { Args: { p_id: string }; Returns: Json };
      delete_event: { Args: { p_id: string }; Returns: void };
      grant_complimentary_event_booking: { Args: { p_event_id: string; p_email: string; p_guest_names: string[]; p_reason: string }; Returns: string };
      list_partner_content_for_management: { Args: Record<string, never>; Returns: ManagedPartnerContent[] };
      list_partner_properties_for_management: { Args: Record<string, never>; Returns: ManagedPartnerProperty[] };
      save_partner: { Args: { p_id: string | null; p_name: string; p_slug: string; p_category: string; p_description: string; p_location: string; p_website: string | null; p_status: string }; Returns: string };
      save_benefit: { Args: { p_id: string | null; p_partner_id: string; p_title: string; p_description: string; p_redemption_instructions: string; p_terms: string; p_status: string }; Returns: string };
      save_partner_property: { Args: { p_id: string | null; p_partner_id: string; p_name: string; p_slug: string; p_address: string; p_status: string }; Returns: string };
      save_partner_property_contact: { Args: { p_property_id: string; p_email: string | null; p_phone: string | null }; Returns: void };
      check_partner_deletion: { Args: { p_id: string }; Returns: Json };
      delete_partner: { Args: { p_id: string }; Returns: void };
      delete_benefit: { Args: { p_id: string }; Returns: void };
      delete_partner_property: { Args: { p_id: string }; Returns: void };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
export type MemberBenefit = Database["public"]["Functions"]["get_active_member_benefits"]["Returns"][number];
export type MemberBenefitCatalogueItem = Database["public"]["Functions"]["get_active_member_benefit_catalogue"]["Returns"][number];
export type MemberEvent = Database["public"]["Functions"]["get_member_events"]["Returns"][number];
export type MyEventBooking = Database["public"]["Functions"]["get_my_event_bookings"]["Returns"][number];
export type StaffEnquiry = Database["public"]["Functions"]["list_enquiries_for_staff"]["Returns"][number];
export type StaffSupportRequest = Database["public"]["Functions"]["list_support_requests_for_staff"]["Returns"][number];
export type AdminRefund = Database["public"]["Functions"]["list_refunds_for_admin"]["Returns"][number];
export type ManagedMember = Database["public"]["Functions"]["list_members_for_management"]["Returns"][number];

export type ManagedPartnerContent = {
  partner_id: string; partner_name: string; slug: string; category: string; partner_description: string;
  location: string; website: string | null; partner_status: "draft" | "active" | "inactive";
  benefit_id: string | null; benefit_title: string | null; benefit_description: string | null;
  redemption_instructions: string | null; terms: string | null; benefit_status: "draft" | "active" | "inactive" | null;
};
export type ManagedPartnerProperty = {
  id: string; partner_id: string; partner_name: string; name: string; slug: string; address: string;
  status: "draft" | "active" | "inactive"; is_primary: boolean; reservation_email: string | null;
  reservation_phone: string | null; created_at: string; updated_at: string;
};

export type MemberAdminRecord = {
  id: string;
  full_name: string | null;
  email: string;
  phone: string | null;
  birthday: string | null;
  locality: string | null;
  profession: string | null;
  industry: string | null;
  member_number: string | null;
  membership_state: Profile["membership_state"];
  account_created_at: string | null;
  last_sign_in_at: string | null;
  profile_updated_at: string | null;
  bookings: { total: number; confirmed: number; pending: number; cancelled: number };
  payments: { paid: number; created: number; failed: number };
  refunds: { pending: number; processed: number };
  support: { total: number; open: number };
  notes: { id: string; note: string; created_at: string; author_name: string }[];
  recent_actions: { action: string; created_at: string; details: Json }[];
};

export type MembershipControl = {
  member_id: string;
  membership_state: Profile["membership_state"];
  plan: "founding_lifetime" | "annual" | null;
  founding_sequence: number | null;
  starts_at: string | null;
  expires_at: string | null;
  payment_offer_expires_at?: string | null;
  founding_places_remaining: number;
  terms: { id: string; plan: string; source: string; status: string; starts_at: string; expires_at: string | null; amount_paise: number | null; payment_method: string | null; transaction_reference: string | null; payment_received_at: string | null; reason: string | null; created_at: string }[];
};
export type ManagedEvent = Database["public"]["Functions"]["list_events_for_management"]["Returns"][number];
