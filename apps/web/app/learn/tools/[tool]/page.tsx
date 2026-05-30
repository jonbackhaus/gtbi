import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { ToolPageContent } from "./tool-page-content";
import type { ToolId } from "./tool-data";
import { TOOLS, TOOL_IDS } from "./tool-data";

interface Props {
  params: Promise<{ tool: string }>;
}

/**
 * Generate static paths for all tool pages at build time.
 * This enables ISR and better performance.
 */
export function generateStaticParams(): { tool: string }[] {
  return TOOL_IDS.map((tool) => ({ tool }));
}

/**
 * Generate SEO metadata for each tool page.
 */
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { tool } = await params;
  const doc = TOOLS[tool as ToolId];

  if (!doc) {
    return {
      title: "Tool Not Found | GTBI Learning Hub",
    };
  }

  return {
    title: `${doc.title} | GTBI Learning Hub`,
    description: doc.tagline,
  };
}

export default async function ToolCardPage({ params }: Props) {
  const { tool } = await params;
  const doc = TOOLS[tool as ToolId];

  if (!doc) {
    notFound();
  }

  return <ToolPageContent tool={doc} />;
}
