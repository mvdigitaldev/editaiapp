import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { createEditAndReserveCredits } from "../_shared/credits.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const MAX_JOBS_PER_USER = 5;
const JOB_LIMIT_WINDOW_HOURS = 1;

interface RequestBody {
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
    return jsonResponse({ success: false, error: "Método não permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const { user_prompt, storage_paths, width, height } = body;

    if (!user_prompt || typeof user_prompt !== "string" || user_prompt.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'user_prompt' é obrigatório e não pode estar vazio" },
        422
      );
    }

    if (!Array.isArray(storage_paths) || storage_paths.length < 1 || storage_paths.length > 8) {
      return jsonResponse(
        { success: false, error: "Campo 'storage_paths' deve ser um array com 1 a 8 paths" },
        422
      );
    }

    if (typeof width !== "number" || typeof height !== "number") {
      return jsonResponse(
        { success: false, error: "Campos 'width' e 'height' são obrigatórios e devem ser números" },
        422
      );
    }

    const outW = Math.floor(width) & ~15;
    const outH = Math.floor(height) & ~15;
    if (outW < 64 || outH < 64) {
      return jsonResponse(
        { success: false, error: "width e height devem ser múltiplos de 16 e >= 64" },
        422
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ success: false, error: "Autenticação obrigatória" }, 401);
    }
    const authClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await authClient.auth.getUser();
    const userId = user?.id ?? null;
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticação obrigatória" }, 401);
    }

    // Validação: todos os paths devem pertencer ao user_id
    for (let i = 0; i < storage_paths.length; i++) {
      const path = storage_paths[i];
      if (typeof path !== "string" || path.trim().length === 0) {
        return jsonResponse({ success: false, error: `Path ${i + 1} inválido` }, 422);
      }
      if (!path.startsWith(`${userId}/`)) {
        return jsonResponse(
          { success: false, error: "Paths inválidos: não pertencem ao usuário" },
          403
        );
      }
    }

    // Limite de jobs por usuário (queued + processing)
    const since = new Date(Date.now() - JOB_LIMIT_WINDOW_HOURS * 60 * 60 * 1000).toISOString();
    const { count, error: countErr } = await supabase
      .from("edits")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .in("status", ["queued", "processing"])
      .gte("created_at", since);

    if (countErr || (count ?? 0) >= MAX_JOBS_PER_USER) {
      return jsonResponse(
        {
          success: false,
          error: `Máximo de ${MAX_JOBS_PER_USER} jobs simultâneos. Aguarde a conclusão de algum antes de enviar outro.`,
        },
        429
      );
    }

    const creditsMulti = 7 + (storage_paths.length - 1) * 3;
    let editId: string;
    let reservationId: string;

    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "multi_image",
        creditsMulti,
        user_prompt.trim(),
        null,
        { promptTextOriginal: user_prompt.trim() }
      );
      editId = result.editId;
      reservationId = result.reservationId;
    } catch (creditErr) {
      const err = creditErr as Error & { status?: number };
      if (err.status === 402) {
        return jsonResponse({ success: false, error: "Créditos insuficientes" }, 402);
      }
      throw creditErr;
    }

    // Enfileirar job
    const { error: enqueueErr } = await supabase.rpc("enqueue_flux_edit_job", {
      p_msg: {
        edit_id: editId,
        user_id: userId,
        reservation_id: reservationId,
        storage_paths,
        user_prompt: user_prompt.trim(),
        width: outW,
        height: outH,
        operation_type: "multi_image",
      },
    });

    if (enqueueErr) {
      const { releaseReservedCredits } = await import("../_shared/credits.ts");
      await releaseReservedCredits(supabase, reservationId, "enqueue_failed");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      console.error("[editar-multi-imagem-flux] Erro ao enfileirar:", enqueueErr);
      return jsonResponse({ success: false, error: "Falha ao enfileirar job" }, 500);
    }

    return jsonResponse({ edit_id: editId });
  } catch (error) {
    console.error("[editar-multi-imagem-flux] Erro:", error);
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : "Erro interno" },
      500
    );
  }
});
