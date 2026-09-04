import { isAdminRequest } from "../../../../Service/auth/session";
import { toErrorResponse } from "../../../../Service/lib/errors";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    return Response.json({ authenticated: await isAdminRequest(request) });
  } catch (error) {
    return toErrorResponse(error);
  }
}
