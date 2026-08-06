import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  getExpirationDays,
  getPhotoStorageStatus,
  storageLimitPayload,
} from "../_shared/plan_limits.ts";

const BUCKET_NAME = "flux-imagens";
const MAX_BASE64_BYTES = 20 * 1024 * 1024;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  client_request_id?: string;
  image_base64: string;
  original_base64: string;
  width?: number;
  height?: number;
  mime_type?: string;
  file_size?: number;
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function decodeBase64(data: string): Uint8Array {
  const binary = atob(data);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function findExistingEdit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  clientRequestId: string,
) {
  const { data } = await supabase
    .from("edits")
    .select("id, image_url, original_image_url")
    .eq("user_id", userId)
    .eq("client_request_id", clientRequestId)
    .maybeSingle();
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Método não permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const imageBase64 = body.image_base64?.trim();
    const originalBase64 = body.original_base64?.trim();

    if (!imageBase64 || !originalBase64) {
      return jsonResponse(
        { error: "Campos image_base64 e original_base64 são obrigatórios" },
        422,
      );
    }

    if (
      imageBase64.length > MAX_BASE64_BYTES ||
      originalBase64.length > MAX_BASE64_BYTES
    ) {
      return jsonResponse({ error: "Imagem excede o tamanho máximo permitido" }, 413);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Autenticação obrigatória" }, 401);
    }

    const authClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await authClient.auth.getUser();
    const userId = user?.id;
    if (!userId) {
      return jsonResponse({ error: "Token inválido ou expirado" }, 401);
    }

    const clientRequestId =
      typeof body.client_request_id === "string" &&
          body.client_request_id.trim().length > 0
        ? body.client_request_id.trim()
        : crypto.randomUUID();

    const existing = await findExistingEdit(supabase, userId, clientRequestId);
    if (existing?.id) {
      return jsonResponse({
        edit_id: existing.id,
        image_url: existing.image_url,
        original_image_url: existing.original_image_url,
        status: "completed",
        reused: true,
      });
    }

    const storage = await getPhotoStorageStatus(supabase, userId);
    if (!storage.ok) {
      return jsonResponse(storageLimitPayload(storage), 403);
    }

    const editedBytes = decodeBase64(imageBase64);
    const originalBytes = decodeBase64(originalBase64);
    const mimeType = body.mime_type?.trim() || "image/jpeg";
    const extension = mimeType.includes("png") ? "png" : "jpg";
    const editKey = `${userId}/manual/${crypto.randomUUID()}.${extension}`;
    const originalKey =
      `${userId}/manual/original_${crypto.randomUUID()}.${extension}`;

    const uploadEdited = await supabase.storage
      .from(BUCKET_NAME)
      .upload(editKey, editedBytes, {
        contentType: mimeType,
        upsert: false,
      });

    if (uploadEdited.error) {
      console.error("[salvar-edicao-manual] upload edited:", uploadEdited.error);
      return jsonResponse({ error: "Falha ao enviar imagem editada" }, 500);
    }

    const uploadOriginal = await supabase.storage
      .from(BUCKET_NAME)
      .upload(originalKey, originalBytes, {
        contentType: mimeType,
        upsert: false,
      });

    if (uploadOriginal.error) {
      await supabase.storage.from(BUCKET_NAME).remove([editKey]);
      console.error(
        "[salvar-edicao-manual] upload original:",
        uploadOriginal.error,
      );
      return jsonResponse({ error: "Falha ao enviar imagem original" }, 500);
    }

    const { data: publicEdited } = supabase.storage
      .from(BUCKET_NAME)
      .getPublicUrl(editKey);
    const { data: publicOriginal } = supabase.storage
      .from(BUCKET_NAME)
      .getPublicUrl(originalKey);

    const expirationDays = await getExpirationDays(supabase, userId);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + expirationDays);

    const insertPayload: Record<string, unknown> = {
      user_id: userId,
      image_id: null,
      prompt_text: null,
      prompt_text_original: null,
      operation_type: "manual_edit",
      status: "completed",
      credits_used: 0,
      image_url: publicEdited.publicUrl,
      original_image_url: publicOriginal.publicUrl,
      expires_at: expiresAt.toISOString(),
      client_request_id: clientRequestId,
      mime_type: mimeType,
      file_size: body.file_size ?? editedBytes.byteLength,
      width: body.width ?? null,
      height: body.height ?? null,
    };

    const { data: edit, error: insertErr } = await supabase
      .from("edits")
      .insert(insertPayload)
      .select("id")
      .single();

    if (insertErr || !edit?.id) {
      await supabase.storage.from(BUCKET_NAME).remove([editKey, originalKey]);
      console.error("[salvar-edicao-manual] insert edit:", insertErr);
      return jsonResponse({ error: "Falha ao registrar edição" }, 500);
    }

    return jsonResponse({
      edit_id: edit.id,
      image_url: publicEdited.publicUrl,
      original_image_url: publicOriginal.publicUrl,
      status: "completed",
    });
  } catch (error) {
    console.error("[salvar-edicao-manual] unexpected:", error);
    return jsonResponse({ error: "Erro interno ao salvar edição manual" }, 500);
  }
});
