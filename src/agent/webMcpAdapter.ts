interface WebMcpService {
  listTools(): ReadonlyArray<{ name: string; description: string; inputSchema: object; readOnly?: boolean }>;
  callTool(name: string, args: Record<string, unknown>, signal?: AbortSignal): Promise<unknown>;
}

interface ModelContext {
  registerTool(tool: {
    name: string;
    description: string;
    inputSchema: object;
    annotations: { readOnlyHint: boolean };
    execute(args: Record<string, unknown>, options?: { signal?: AbortSignal }): Promise<unknown>;
  }, options: { signal: AbortSignal }): void | Promise<void>;
  waitForToolsUntil?(ready: Promise<unknown>): void;
}

export function getWebMcpContext(): ModelContext | undefined {
  if (typeof window === 'undefined' || window.top !== window) return undefined;
  const context = (document as Document & { modelContext?: ModelContext }).modelContext;
  return typeof context?.registerTool === 'function' ? context : undefined;
}

export async function registerWebMcpTools(
  service: WebMcpService,
  context: ModelContext,
  controller = new AbortController(),
): Promise<() => void> {
  const register = async () => {
    for (const { name, description, inputSchema, readOnly } of service.listTools()) {
      controller.signal.throwIfAborted();
      await context.registerTool({
        name, description, inputSchema,
        annotations: { readOnlyHint: readOnly ?? true },
        async execute(args, options) {
          controller.signal.throwIfAborted();
          options?.signal?.throwIfAborted();
          const result = await service.callTool(name, args, options?.signal);
          controller.signal.throwIfAborted();
          options?.signal?.throwIfAborted();
          return result;
        },
      }, { signal: controller.signal });
    }
  };
  try {
    const ready = register();
    context.waitForToolsUntil?.(ready.catch(() => undefined));
    await ready;
  } catch (error) {
    controller.abort();
    throw error;
  }
  return () => controller.abort();
}
