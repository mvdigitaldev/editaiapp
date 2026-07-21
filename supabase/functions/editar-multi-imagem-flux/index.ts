import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  enforceBflUserJobLimit,
  enqueueBflInitJob,
} from "../_shared/bfl_queue.ts";
import {
  createEditAndReserveCredits,
  releaseReservedCredits,
} from "../_shared/credits.ts";
import { triggerBflInitWorker } from "../_shared/bfl_init_invoke.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  client_request_id: string;
  user_prompt: string;
  storage_paths: string[];
  width: number;
  height: number;
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo nao permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const { client_request_id, user_prompt, storage_paths, width, height } = body;

    if (!client_request_id || typeof client_request_id !== "string" || client_request_id.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'client_request_id' e obrigatorio" }, 422);
    }

    if (!user_prompt || typeof user_prompt !== "string" || user_prompt.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'user_prompt' e obrigatorio" }, 422);
    }

    if (!Array.isArray(storage_paths) || storage_paths.length < 1 || storage_paths.length > 8) {
      return jsonResponse({ success: false, error: "Campo 'storage_paths' deve ter de 1 a 8 paths" }, 422);
    }

    if (typeof width !== "number" || typeof height !== "number") {
      return jsonResponse({ success: false, error: "Campos 'width' e 'height' sao obrigatorios" }, 422);
    }

    const outW = Math.floor(width) & ~15;
    const outH = Math.floor(height) & ~15;
    if (outW < 64 || outH < 64) {
      return jsonResponse({ success: false, error: "width e height devem ser multiplos de 16 e >= 64" }, 422);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ success: false, error: "Autenticacao obrigatoria" }, 401);
    }
    const authClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await authClient.auth.getUser();
    const userId = user?.id ?? null;
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticacao obrigatoria" }, 401);
    }

    for (let index = 0; index < storage_paths.length; index++) {
      const path = storage_paths[index];
      if (typeof path !== "string" || path.trim().length === 0) {
        return jsonResponse({ success: false, error: `Path ${index + 1} invalido` }, 422);
      }
      if (!path.startsWith(`${userId}/`)) {
        return jsonResponse({ success: false, error: "Paths invalidos: nao pertencem ao usuario" }, 403);
      }
    }

    await enforceBflUserJobLimit(supabase, userId);

    const creditsMulti = 7 + (storage_paths.length - 1) * 3;
    let editId = "";
    let reservationId = "";
    let acceptedAt = new Date().toISOString();

    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "multi_image",
        creditsMulti,
        user_prompt.trim(),
        null,
        {
          promptTextOriginal: user_prompt.trim(),
          clientRequestId: client_request_id.trim(),
        },
      );
      editId = result.editId;
      reservationId = result.reservationId;
      acceptedAt = result.acceptedAt;
      if (result.reused) {
        return jsonResponse({
          edit_id: result.editId,
          task_id: result.taskId,
          status: result.status,
          accepted_at: result.acceptedAt,
        });
      }
    } catch (creditErr) {
      const err = creditErr as Error & { status?: number };
      if (err.status === 402) {
        return jsonResponse({ success: false, error: "Creditos insuficientes" }, 402);
      }
      if (err.status === 429) {
        return jsonResponse({ success: false, error: err.message }, 429);
      }
      throw creditErr;
    }

    try {
      await enqueueBflInitJob(supabase, {
        edit_id: editId,
        user_id: userId,
        reservation_id: reservationId,
        operation_type: "multi_image",
        prompt_text: user_prompt.trim(),
        storage_paths,
        width: outW,
        height: outH,
        enqueued_at: new Date().toISOString(),
      });
    } catch (enqueueErr) {
      await releaseReservedCredits(supabase, reservationId, "enqueue_failed");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      console.error("[editar-multi-imagem-flux] Erro ao enfileirar:", enqueueErr);
      return jsonResponse({ success: false, error: "Falha ao enfileirar job" }, 500);
    }

    await triggerBflInitWorker(supabaseUrl);

    return jsonResponse({
      edit_id: editId,
      status: "queued",
      accepted_at: acceptedAt,
    });
  } catch (error) {
    console.error("[editar-multi-imagem-flux] Erro:", error);
    const err = error as Error & { status?: number };
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : "Erro interno" },
      err.status ?? 500,
    );
  }
});
