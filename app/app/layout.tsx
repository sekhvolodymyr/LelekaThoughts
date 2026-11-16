import type { Metadata } from "next";
import "./globals.css";
import "@/components/leleka/styles.css";
import "@/components/leleka/themes.css";
import "@/components/leleka/brand.css";

export const metadata: Metadata = {
  title: "LelekaThoughts — ідеї, що продовжуються",
  description: "Діліться творчим процесом, розвивайте ідеї в ланцюжках і зберігайте історії у серіях сторіс.",
  manifest: "/manifest.webmanifest",
  appleWebApp: {capable: true, title: "LelekaThoughts", statusBarStyle: "default"},
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
    apple: "/icon-192.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="uk" suppressHydrationWarning>
      <body className="antialiased">{children}</body>
    </html>
  );
}
