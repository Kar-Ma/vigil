import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://keep-vigil.vercel.app"),
  title: "Vigil: Secure Camera — Available on the App Store",
  description: "Download Vigil, an open-source iOS safety camera for recording important moments and keeping completed recordings under your control.",
  icons: { icon: "/vigil-icon.png", shortcut: "/vigil-icon.png" },
  alternates: { canonical: "/" },
  itunes: { appId: "6793280070" },
  openGraph: {
    title: "Vigil: Secure Camera — Available on the App Store",
    description: "Download Vigil, an open-source iOS safety camera for recording important moments and keeping completed recordings under your control.",
    url: "/",
    siteName: "Vigil",
    images: ["/vigil-icon.png"],
  },
  twitter: {
    card: "summary",
    title: "Vigil: Secure Camera — Available on the App Store",
    description: "Download Vigil, an open-source iOS safety camera for recording important moments and keeping completed recordings under your control.",
    images: ["/vigil-icon.png"],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
