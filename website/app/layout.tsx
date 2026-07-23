import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://keep-vigil.vercel.app"),
  title: "Vigil — Stay close to what matters",
  description: "An open-source iOS safety app for recording important moments and making completed recordings harder to lose or casually access.",
  icons: { icon: "/vigil-icon.png", shortcut: "/vigil-icon.png" },
  alternates: { canonical: "/" },
  openGraph: {
    title: "Vigil — Stay close to what matters",
    description: "An open-source iOS safety app for recording important moments and making completed recordings harder to lose or casually access.",
    url: "/",
    siteName: "Vigil",
    images: ["/vigil-icon.png"],
  },
  twitter: {
    card: "summary",
    title: "Vigil — Stay close to what matters",
    description: "An open-source iOS safety app for recording important moments and making completed recordings harder to lose or casually access.",
    images: ["/vigil-icon.png"],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
