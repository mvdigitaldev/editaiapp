import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET_NAME = "flux-imagens";

interface WebhookPayload {
  id: string;
  status: string;
  result?: { sample?: string };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  try {
    const payload = (await req.json()) as WebhookPayload;
    const { id: taskId, status, result } = payload;

    if (!taskId) {
      console.error("[flux-webhook] Payload sem id:", payload);
      return new Response(null, { status: 400 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    if (status === "Error" || status === "Content Moderated" || status === "Request Moderated") {
      const errMsg = status === "Content Moderated" || status === "Request Moderated"
        ? "Conteúdo moderado pela API"
        : "Erro na geração da imagem";
      const { data: task } = await supabase
        .from("flux_tasks")
        .select("edit_id, user_id")
        .eq("task_id", taskId)
        .single();
      if (task?.edit_id && task?.user_id) {
        const { data: edit } = await supabase
          .from("edits")
          .select("credits_used")
          .eq("id", task.edit_id)
          .single();
        if (edit?.credits_used && edit.credits_used > 0) {
          await supabase.rpc("refund_credits_for_edit", {
            p_user_id: task.user_id,
            p_credits: edit.credits_used,
            p_edit_id: task.edit_id,
          });
        }
        await supabase.from("edits").update({ status: "failed" }).eq("id", task.edit_id);
      }
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: errMsg,
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return new Response(null, { status: 200 });
    }

    if (status !== "Ready") {
      return new Response(null, { status: 200 });
    }

    const sampleUrl = result?.sample;
    if (!sampleUrl || typeof sampleUrl !== "string") {
      console.error("[flux-webhook] Resultado sem sample:", payload);
      const { data: task } = await supabase
        .from("flux_tasks")
        .select("edit_id, user_id")
        .eq("task_id", taskId)
        .single();
      if (task?.edit_id && task?.user_id) {
        const { data: edit } = await supabase
          .from("edits")
          .select("credits_used")
          .eq("id", task.edit_id)
          .single();
        if (edit?.credits_used && edit.credits_used > 0) {
          await supabase.rpc("refund_credits_for_edit", {
            p_user_id: task.user_id,
            p_credits: edit.credits_used,
            p_edit_id: task.edit_id,
          });
        }
        await supabase.from("edits").update({ status: "failed" }).eq("id", task.edit_id);
      }
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: "Resultado inválido da API",
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return new Response(null, { status: 200 });
    }

    const imgRes = await fetch(sampleUrl);
    if (!imgRes.ok) {
      console.error("[flux-webhook] Erro ao baixar imagem:", imgRes.status);
      const { data: task } = await supabase
        .from("flux_tasks")
        .select("edit_id, user_id")
        .eq("task_id", taskId)
        .single();
      if (task?.edit_id && task?.user_id) {
        const { data: edit } = await supabase
          .from("edits")
          .select("credits_used")
          .eq("id", task.edit_id)
          .single();
        if (edit?.credits_used && edit.credits_used > 0) {
          await supabase.rpc("refund_credits_for_edit", {
            p_user_id: task.user_id,
            p_credits: edit.credits_used,
            p_edit_id: task.edit_id,
          });
        }
        await supabase.from("edits").update({ status: "failed" }).eq("id", task.edit_id);
      }
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: "Falha ao obter imagem gerada",
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return new Response(null, { status: 200 });
    }

    const imgBytes = await imgRes.arrayBuffer();
    const timestamp = Math.floor(Date.now() / 1000);
    const fileName = `default/${timestamp}_${taskId}.jpeg`;

    const { error: uploadError } = await supabase.storage
      .from(BUCKET_NAME)
      .upload(fileName, imgBytes, {
        contentType: "image/jpeg",
        upsert: true,
      });

    if (uploadError) {
      console.error("[flux-webhook] Erro upload:", uploadError);
      const { data: task } = await supabase
        .from("flux_tasks")
        .select("edit_id, user_id")
        .eq("task_id", taskId)
        .single();
      if (task?.edit_id && task?.user_id) {
        const { data: edit } = await supabase
          .from("edits")
          .select("credits_used")
          .eq("id", task.edit_id)
          .single();
        if (edit?.credits_used && edit.credits_used > 0) {
          await supabase.rpc("refund_credits_for_edit", {
            p_user_id: task.user_id,
            p_credits: edit.credits_used,
            p_edit_id: task.edit_id,
          });
        }
        await supabase.from("edits").update({ status: "failed" }).eq("id", task.edit_id);
      }
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: "Falha ao salvar imagem",
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return new Response(null, { status: 200 });
    }

    const { data: urlData } = supabase.storage.from(BUCKET_NAME).getPublicUrl(fileName);

    await supabase
      .from("flux_tasks")
      .update({
        status: "ready",
        image_url: urlData.publicUrl,
        updated_at: new Date().toISOString(),
      })
      .eq("task_id", taskId);

    const { data: task } = await supabase
      .from("flux_tasks")
      .select("edit_id")
      .eq("task_id", taskId)
      .single();
    if (task?.edit_id) {
      await supabase.from("edits").update({ status: "completed" }).eq("id", task.edit_id);
    }

    return new Response(null, { status: 200 });
  } catch (error) {
    console.error("[flux-webhook] Erro:", error);
    return new Response(null, { status: 500 });
  }
});
