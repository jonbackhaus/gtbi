import { notFound } from "next/navigation";
import { createSocialImage } from "@/lib/social-image";
import { getLessonBySlug } from "@/lib/lessons";

export const runtime = "edge";

export const alt = "GTBI Lesson";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug);

  if (!lesson) {
    notFound();
  }

  return createSocialImage(
    {
      badge: `Lesson ${lesson.id + 1}`,
      title: lesson.title,
      description: lesson.description,
      path: `/learn/${lesson.slug}`,
      theme: "learn",
      tags: [lesson.duration, "Learning Hub", "GTBI"],
    },
    "twitter"
  );
}
