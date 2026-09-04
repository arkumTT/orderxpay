import type { Metadata } from "next";
import { Urbanist, Geist_Mono } from "next/font/google";
import "./globals.css";

// Urbanist is the OrderxPay brand typeface — same choice as src/mobile
// (app_theme.dart uses GoogleFonts.urbanist) and the Claude Design handoff
// (OrderxPay.dc.html loads it explicitly). Replaces the Next.js starter
// default (Geist Sans) sitewide — this app has no other established
// typography to preserve (the root page is a placeholder; the catalog
// page has no deliberate font choice yet).
const urbanist = Urbanist({
  variable: "--font-urbanist",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "OrderxPay",
  description: "Pay a merchant or browse a catalog on OrderxPay",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${urbanist.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
