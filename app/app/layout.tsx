import type { Metadata } from "next";
import "./globals.css";
import "@/components/leleka/styles.css";
import "@/components/leleka/themes.css";
import "@/components/leleka/brand.css";
import "@/components/leleka/blog.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://lelekathoughts.vercel.app"),
  title: "LelekaThoughts (Лелека) — українська соцмережа",
  description: "LelekaThoughts, або «Лелека», — українська соцмережа для креаторів. Діліться ідеями, створюйте ланцюжки постів і серії сторіс та знаходьте свою спільноту.",
  alternates: {canonical: "/"},
  robots: {index: true, follow: true},
  verification: {google: process.env.GOOGLE_SITE_VERIFICATION || undefined},
  openGraph: {
    type: "website", locale: "uk_UA", url: "/", siteName: "LelekaThoughts",
    title: "LelekaThoughts — українська соцмережа для креаторів",
    description: "Лелека — місце, де ідеї ростуть разом. Пости, ланцюжки та сторіс для творчої спільноти.",
    images: [{url: "/social-preview.png", width: 1200, height: 630, alt: "LelekaThoughts — українська соцмережа. Ідеї, що продовжуються."}],
  },
  twitter: {card: "summary_large_image",title: "LelekaThoughts — українська соцмережа",description: "Ділися задумом, показуй творчий процес і знаходь свою спільноту.",images: ["/social-preview.png"]},
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
