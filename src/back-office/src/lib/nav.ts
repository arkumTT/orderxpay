export type NavItem = {
  label: string;
  href: string;
  section: string; // architecture doc section reference
};

export const NAV_ITEMS: NavItem[] = [
  { label: "Merchants", href: "/merchants", section: "7.1" },
  { label: "KYC Review", href: "/merchants/kyc-review", section: "7.1" },
  { label: "Settlements", href: "/settlements", section: "7.2" },
  { label: "Integrations", href: "/integrations", section: "7.3" },
  { label: "Pricing", href: "/pricing", section: "7.4" },
  { label: "Reporting", href: "/reporting", section: "7.5" },
  { label: "Risk & Fraud", href: "/risk", section: "7.6" },
  { label: "Disputes", href: "/disputes", section: "7.7" },
  { label: "Admin Users", href: "/admin-users", section: "7.8" },
  { label: "Audit Log", href: "/audit-log", section: "7.9" },
  { label: "Support", href: "/support", section: "7.10" },
];
