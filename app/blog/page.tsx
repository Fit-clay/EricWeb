import type { Metadata } from "next";
import { BlogLibrary } from "./BlogLibrary";

export const metadata: Metadata = {
  title: "藏文入库 | 貔貅",
};

export default function BlogPage() {
  return <BlogLibrary />;
}
