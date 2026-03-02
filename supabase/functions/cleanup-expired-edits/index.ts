import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET_NAME = "flux-imagens";
const BATCH_LIMIT = 500;

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function extractStoragePathFromPublicUrl(url: string): string | null {
  if (!url || typeof url !== "string") return null;

  const prefix = `${BUCKET_NAME}/`;
  const idx = url.indexOf(prefix);
  if (idx === -1) return null;

  let path = url.slice(idx + prefix.length);
  const queryIndex = path.indexOf("?");
  if (queryIndex !== -1) {
    path = path.slice(0, queryIndex);
  }

  path = path.trim();
  return path.length > 0 ? path : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Método não permitido" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[cleanup-expired-edits] SUPABASE_URL ou SERVICE_ROLE_KEY ausente");
      return jsonResponse(
        { success: false, error: "Configuração do Supabase ausente" },
        500,
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const nowIso = new Date().toISOString();

    const { data: edits, error: selectError } = await supabase
      .from("edits")
      .select("id, image_url")
      .not("expires_at", "is", null)
      .lt("expires_at", nowIso)
      .limit(BATCH_LIMIT);

    if (selectError) {
      console.error("[cleanup-expired-edits] Erro ao buscar edits expirados:", selectError);
      return jsonResponse(
        { success: false, error: "Erro ao buscar edits expirados" },
        500,
      );
    }

    if (!edits || edits.length === 0) {
      return jsonResponse({
        success: true,
        deleted_count: 0,
        storage_paths_deleted: 0,
      });
    }

    const idsToDelete: string[] = [];
    const storagePaths: string[] = [];

    for (const row of edits) {
      const id = row.id as string | undefined;
      const imageUrl = row.image_url as string | null | undefined;

      if (id) {
        idsToDelete.push(id);
      }

      if (imageUrl) {
        const path = extractStoragePathFromPublicUrl(imageUrl);
        if (path) {
          storagePaths.push(path);
        }
      }
    }

    let storageDeleted = 0;

    if (storagePaths.length > 0) {
      const { error: storageError } = await supabase.storage
        .from(BUCKET_NAME)
        .remove(storagePaths);

      if (storageError) {
        console.warn(
          "[cleanup-expired-edits] Erro ao remover arquivos do storage (ignorando):",
          storageError,
        );
      } else {
        storageDeleted = storagePaths.length;
      }
    }

    if (idsToDelete.length === 0) {
      return jsonResponse({
        success: true,
        deleted_count: 0,
        storage_paths_deleted: storageDeleted,
      });
    }

    const { error: deleteError } = await supabase
      .from("edits")
      .delete()
      .in("id", idsToDelete);

    if (deleteError) {
      console.error("[cleanup-expired-edits] Erro ao deletar edits expirados:", deleteError);
      return jsonResponse(
        { success: false, error: "Erro ao deletar edits expirados" },
        500,
      );
    }

    return jsonResponse({
      success: true,
      deleted_count: idsToDelete.length,
      storage_paths_deleted: storageDeleted,
    });
  } catch (error) {
    console.error("[cleanup-expired-edits] Erro inesperado:", error);
    return jsonResponse(
      { success: false, error: "Erro interno ao limpar edits expirados" },
      500,
    );
  }
});

