const BFL_INIT_WORKER_PATH = "/functions/v1/bfl-init-worker";

export async function triggerBflInitWorker(
  supabaseUrl: string,
): Promise<void> {
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) {
    return;
  }

  const workerUrl = `${supabaseUrl}${BFL_INIT_WORKER_PATH}`;

  try {
    await fetch(workerUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({ source: "enqueue_kick" }),
      signal: AbortSignal.timeout(1500),
    });
  } catch (error) {
    console.warn("[bfl-init] Kick imediato do worker falhou:", error);
  }
}
