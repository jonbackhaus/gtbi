import { NextResponse } from "next/server";

// Ensure this route is always dynamic (never cached at build time)
export const dynamic = "force-dynamic";

/**
 * GET /install
 *
 * Redirects to the raw install.sh script on GitHub.
 * This allows users to run: curl -fsSL https://agent-flywheel.com/install | bash
 *
 * The -L flag in curl follows redirects, so this works seamlessly.
 */
export async function GET() {
  const scriptUrl =
    "https://raw.githubusercontent.com/jonbackhaus/gtbi/main/install.sh";

  // Create redirect response with cache-control headers to prevent caching
  const response = NextResponse.redirect(scriptUrl, 302);
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  response.headers.set("Pragma", "no-cache");
  response.headers.set("Expires", "0");

  return response;
}
