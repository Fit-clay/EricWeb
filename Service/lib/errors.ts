export class ServiceError extends Error {
  status: number;

  constructor(message: string, status = 500) {
    super(message);
    this.name = "ServiceError";
    this.status = status;
  }
}

export function toErrorResponse(error: unknown) {
  if (error instanceof ServiceError) {
    return Response.json({ error: error.message }, { status: error.status });
  }

  const message = error instanceof Error ? error.message : "Unexpected error";
  const detail =
    error instanceof Error && error.cause instanceof Error ? error.cause.message : "";
  const combined = `${message}\n${detail}`;

  if (combined.includes("no such table") || combined.includes('from "articles"')) {
    return Response.json(
      {
        error:
          "文章数据库表不可用。请确认 DATABASE_PATH 所在目录存在，并允许网站服务用户读写。",
      },
      { status: 500 }
    );
  }

  return Response.json({ error: message }, { status: 500 });
}
