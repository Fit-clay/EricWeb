import { createLogoutCookie } from "../../../../Service/auth/session";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST() {
  return Response.json(
    { authenticated: false },
    {
      headers: {
        "set-cookie": createLogoutCookie(),
      },
    }
  );
}
