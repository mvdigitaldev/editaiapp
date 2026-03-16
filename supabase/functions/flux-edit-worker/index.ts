import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { processFluxEditJob, type FluxEditJobPayload } from "../_shared/flux_edit_processor.ts";

const QUEUE_NAME = "flux-edit-jobs";
const MAX_READ_CT = 3;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const { data: rows, error: readErr } = await supabase.rpc("read_flux_edit_job");

    if (readErr) {
      console.error("[flux-edit-worker] Erro ao ler fila:", readErr);
      return new Response(JSON.stringify({ ok: false, error: readErr.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const messages = Array.isArray(rows) ? rows : rows ? [rows] : [];
    if (messages.length === 0) {
      return new Response(JSON.stringify({ ok: true, processed: 0 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const msg = messages[0] as { msg_id: number; read_ct: number; message: FluxEditJobPayload };
    const { msg_id, read_ct, message } = msg;

    if (read_ct > MAX_READ_CT) {
      await supabase.rpc("archive_flux_edit_message", { p_msg_id: msg_id });
      const { releaseReservedCredits } = await import("../_shared/credits.ts");
      await releaseReservedCredits(supabase, message.reservation_id, "max_retries_exceeded");
      await supabase
        .from("edits")
        .update({ status: "failed" })
        .eq("id", message.edit_id);
      console.warn("[flux-edit-worker] Job arquivado (read_ct > 3):", message.edit_id);
      return new Response(JSON.stringify({ ok: true, processed: 1, archived: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: edit } = await supabase
      .from("edits")
      .select("status, started_at")
      .eq("id", message.edit_id)
      .single();

    if (!edit) {
      await supabase.rpc("delete_flux_edit_message", { p_msg_id: msg_id });
      return new Response(JSON.stringify({ ok: true, processed: 1 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const status = edit.status as string;
    if (status === "completed" || status === "failed") {
      await supabase.rpc("delete_flux_edit_message", { p_msg_id: msg_id });
      return new Response(JSON.stringify({ ok: true, processed: 1, skipped: status }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (status === "processing") {
      const startedAt = edit.started_at ? new Date(edit.started_at).getTime() : 0;
      if (Date.now() - startedAt > 10 * 60 * 1000) {
        const { releaseReservedCredits } = await import("../_shared/credits.ts");
        await releaseReservedCredits(supabase, message.reservation_id, "stale_processing");
        await supabase
          .from("edits")
          .update({ status: "failed" })
          .eq("id", message.edit_id);
        await supabase.rpc("archive_flux_edit_message", { p_msg_id: msg_id });
      }
      return new Response(JSON.stringify({ ok: true, processed: 0 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: updated } = await supabase
      .from("edits")
      .update({ status: "processing", started_at: new Date().toISOString() })
      .eq("id", message.edit_id)
      .eq("status", "queued")
      .select("id")
      .maybeSingle();

    if (!updated) {
      await supabase.rpc("delete_flux_edit_message", { p_msg_id: msg_id });
      return new Response(JSON.stringify({ ok: true, processed: 1 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const result = await processFluxEditJob(supabase, message);

    if ("error" in result) {
      await supabase
        .from("edits")
        .update({ status: "failed" })
        .eq("id", message.edit_id);
      console.error("[flux-edit-worker] Erro ao processar:", message.edit_id, result.error);
    }

    await supabase.rpc("delete_flux_edit_message", { p_msg_id: msg_id });

    const { data: metrics } = await supabase.rpc("flux_edit_queue_metrics");
    const queueLength = Array.isArray(metrics) && metrics[0] ? (metrics[0] as { queue_length: number }).queue_length : 0;

    if (queueLength > 0) {
      const workerUrl = `${supabaseUrl}/functions/v1/flux-edit-worker`;
      const invokeSecret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      fetch(workerUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${invokeSecret}`,
        },
      }).catch((e) => console.warn("[flux-edit-worker] Self-invoke failed:", e));
    }

    return new Response(
      JSON.stringify({ ok: true, processed: 1, taskId: "taskId" in result ? result.taskId : null }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[flux-edit-worker] Erro:", error);
    return new Response(
      JSON.stringify({ ok: false, error: error instanceof Error ? error.message : "Erro" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
