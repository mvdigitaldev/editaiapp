import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET_NAME = "flux-imagens";
const MAX_EDIT_IDS = 50;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  edit_ids: string[];
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

/**
 * Extrai o path do storage a partir da URL pública.
 * Formato: https://{project}.supabase.co/storage/v1/object/public/flux-imagens/default/xxx.jpeg
 */
function extractStoragePath(imageUrl: string): string | null {
  if (!imageUrl || typeof imageUrl !== "string") return null;
  const prefix = `${BUCKET_NAME}/`;
  const idx = imageUrl.indexOf(prefix);
  if (idx === -1) return null;
  return imageUrl.slice(idx + prefix.length).split("?")[0]?.trim() || null;
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
    const editIds = body?.edit_ids;

    if (!Array.isArray(editIds) || editIds.length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'edit_ids' deve ser um array não vazio" },
        422
      );
    }

    if (editIds.length > MAX_EDIT_IDS) {
      return jsonResponse(
        { success: false, error: `Máximo de ${MAX_EDIT_IDS} fotos por requisição` },
        422
      );
    }

    const validIds = editIds.filter((id) => typeof id === "string" && id.trim().length > 0);
    if (validIds.length === 0) {
      return jsonResponse({ success: false, error: "Nenhum ID válido" }, 422);
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
      return jsonResponse({ success: false, error: "Token inválido ou expirado" }, 401);
    }

    // 1. Buscar edits que pertencem ao usuário (para extrair paths do storage)
    const { data: editsToDelete, error: fetchErr } = await supabase
      .from("edits")
      .select("id, image_url, original_image_url")
      .in("id", validIds)
      .eq("user_id", userId);

    if (fetchErr) {
      console.error("[delete-edits] Erro ao buscar edits:", fetchErr);
      return jsonResponse({ success: false, error: "Erro ao buscar fotos" }, 500);
    }

    const edits = (editsToDelete ?? []) as Array<{ id: string; image_url: string | null; original_image_url?: string | null }>;
    const idsToDelete = edits.map((e) => e.id);

    if (idsToDelete.length === 0) {
      return jsonResponse({ success: true, deleted_count: 0 });
    }

    // 2. Remover arquivos do storage em batch (editada e original)
    const storagePaths: string[] = [];
    for (const edit of edits) {
      const imageUrl = edit.image_url;
      const originalImageUrl = edit.original_image_url;
      if (imageUrl && imageUrl.includes(BUCKET_NAME)) {
        const path = extractStoragePath(imageUrl);
        if (path) storagePaths.push(path);
      }
      if (originalImageUrl && originalImageUrl.includes(BUCKET_NAME)) {
        const path = extractStoragePath(originalImageUrl);
        if (path) storagePaths.push(path);
      }
    }
    if (storagePaths.length > 0) {
      try {
        await supabase.storage.from(BUCKET_NAME).remove(storagePaths);
      } catch (storageErr) {
        console.warn("[delete-edits] Erro ao remover do storage (ignorado):", storageErr);
      }
    }

    // 3. DELETE em batch (um a um para evitar problemas com .in() + .select())
    let deletedCount = 0;
    for (const editId of idsToDelete) {
      const { error: deleteErr } = await supabase.from("edits").delete().eq("id", editId);
      if (!deleteErr) deletedCount++;
      else console.warn("[delete-edits] Erro ao deletar edit", editId, deleteErr);
    }
    return jsonResponse({ success: true, deleted_count: deletedCount });
  } catch (error) {
    console.error("[delete-edits] Erro:", error);
    return jsonResponse(
      { success: false, error: "Erro interno ao excluir fotos" },
      500
    );
  }
});
