import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "貔貅",
  description: "只进不出的灵感、工具与页面收藏。",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
