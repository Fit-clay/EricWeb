import type { Metadata } from "next";
import { SectionPage } from "../section-page";

export const metadata: Metadata = {
  title: "器用开匣 | 貔貅",
};

export default function ToolsPage() {
  return (
    <SectionPage
      seal="器"
      label="器用开匣"
      note="放些顺手的小器具，助日常一臂。"
      items={["提示词整理器", "链接预览台", "轻量任务清单"]}
    />
  );
}
