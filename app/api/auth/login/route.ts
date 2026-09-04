import { createLoginCookie, loginAdmin } from "../../../../Service/auth/session";
import { toErrorResponse } from "../../../../Service/lib/errors";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const payload = (await request.json()) as { name?: string; password?: string };
    const token = await loginAdmin(payload.name ?? "", payload.password ?? "");
    return Response.json(
      { authenticated: true },
      {
        status: 200,
        headers: {
          "set-cookie": createLoginCookie(token),
        },
      }
    );
  } catch (error) {
    return toErrorResponse(error);
  }
}
