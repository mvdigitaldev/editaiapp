import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Extrai o user id direto do payload do JWT (base64).
 * Sem chamadas de rede — o gateway já validou a assinatura (verify_jwt ou auth_user nos logs).
 */
function extractUserIdFromJwt(token: string): string | null {
  try {
    let t = token.trim();
    if (t.toLowerCase().startsWith("bearer ")) t = t.slice(7).trim();
    const parts = t.split(".");
    if (parts.length !== 3) return null;
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
    const payload = JSON.parse(atob(b64 + pad)) as { sub?: string; exp?: number };
    if (typeof payload.exp === "number" && payload.exp < Date.now() / 1000) return null;
    const sub = payload.sub;
    return typeof sub === "string" && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}

/**
 * Pega o JWT do header Authorization ou do campo access_token no body.
 */
function resolveUserId(req: Request, bodyAccessToken?: string | null): string | null {
  const sources = [
    req.headers.get("Authorization"),
    req.headers.get("authorization"),
    req.headers.get("x-forwarded-authorization"),
    typeof bodyAccessToken === "string" ? bodyAccessToken : null,
  ];
  for (const raw of sources) {
    if (!raw?.trim()) continue;
    const uid = extractUserIdFromJwt(raw);
    if (uid) return uid;
  }
  return null;
}

const OPENAI_API_URL = "https://api.openai.com/v1";
const EDIT_INPUTS_BUCKET = "edit-inputs";
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  modelo_id: string;
  storage_path: string;
  width?: number;
  height?: number;
  /** Fallback quando o gateway não repassa Authorization (ex.: app móvel). */
  access_token?: string;
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function openaiJsonFromVision(
  imageBase64: string,
  userText: string,
  openaiKey: string,
): Promise<string> {
  const dataUrl = imageBase64.startsWith("data:")
    ? imageBase64
    : `data:image/jpeg;base64,${imageBase64}`;
  const res = await fetch(`${OPENAI_API_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openaiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0.3,
      max_tokens: 600,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: userText },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
    }),
  });
  if (!res.ok) throw new Error(`OpenAI error: ${res.status}`);
  const data = await res.json();
  return data.choices[0]?.message?.content?.trim() ?? "";
}

function parseSuggestionsJson(raw: string): string[] {
  try {
    const parsed = JSON.parse(raw) as { suggestions?: unknown };
    const list = parsed.suggestions;
    if (!Array.isArray(list)) return [];
    return list
      .filter((x): x is string => typeof x === "string" && x.trim().length > 0)
      .map((s) => s.trim())
      .slice(0, 8);
  } catch {
    return [];
  }
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
    const { modelo_id, storage_path, width, height, access_token } = body;

    if (!modelo_id || typeof modelo_id !== "string" || modelo_id.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'modelo_id' é obrigatório" },
        422,
      );
    }

    if (!storage_path || typeof storage_path !== "string" || storage_path.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'storage_path' é obrigatório" },
        422,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const userId = resolveUserId(req, access_token);
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticação obrigatória" }, 401);
    }

    if (!storage_path.startsWith(`${userId}/`)) {
      return jsonResponse({ success: false, error: "Path inválido: não pertence ao usuário" }, 403);
    }

    const { data: modelo, error: modeloErr } = await supabase
      .from("modelos")
      .select("id, prompt_padrao, categoria_id, ativo")
      .eq("id", modelo_id.trim())
      .eq("ativo", true)
      .maybeSingle();

    if (modeloErr || !modelo) {
      return jsonResponse(
        { success: false, error: "Modelo não encontrado ou inativo" },
        404,
      );
    }

    const { data: categoriaRow } = await supabase
      .from("categorias")
      .select("edit_mode")
      .eq("id", modelo.categoria_id as string)
      .maybeSingle();

    const editMode = (categoriaRow?.edit_mode as string | undefined) ?? "guided";
    if (editMode !== "guided") {
      return jsonResponse(
        { success: false, error: "Este modelo não usa o fluxo de sugestões" },
        422,
      );
    }

    const { data: bytes, error: downloadErr } = await supabase.storage
      .from(EDIT_INPUTS_BUCKET)
      .download(storage_path);

    if (downloadErr || !bytes) {
      console.error("[modelo-sugerir-melhorias] download:", storage_path, downloadErr);
      return jsonResponse({ success: false, error: "Imagem não encontrada ou inacessível" }, 422);
    }

    if (bytes.size > MAX_IMAGE_BYTES) {
      return jsonResponse({ success: false, error: "Imagem muito grande. Máximo: 2 MB." }, 422);
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      return jsonResponse({ success: false, error: "Configuração do serviço indisponível" }, 500);
    }

    const arr = new Uint8Array(bytes.size);
    arr.set(new Uint8Array(await bytes.arrayBuffer()));
    let outStr = "";
    for (let j = 0; j < arr.length; j++) outStr += String.fromCharCode(arr[j]);
    const resizedBase64 = btoa(outStr);

    void width;
    void height;

    const basePrompt = ((modelo.prompt_padrao as string) ?? "").trim() || "Melhorar a imagem para uso profissional.";

    const instruction =
      `Com base na imagem e no objetivo de edição abaixo, gere exatamente 5 sugestões curtas e concretas de melhoria que um usuário poderia escolher para um editor de imagens com IA.
Objetivo base (contexto): """${basePrompt.replace(/"/g, "'")}"""

Regras:
- Cada sugestão: uma frase curta em português do Brasil.
- Sejam específicas para ESTA foto (observe o que aparece na imagem).
- Não repetir ideias parecidas.
- Resposta APENAS como JSON: {"suggestions":["sugestão1","sugestão2","sugestão3","sugestão4","sugestão5"]}`;

    let raw: string;
    try {
      raw = await openaiJsonFromVision(resizedBase64, instruction, openaiKey);
    } catch (e) {
      console.error("[modelo-sugerir-melhorias] OpenAI:", e);
      return jsonResponse(
        { success: false, error: "Falha ao analisar a imagem. Tente outra foto ou formato JPEG/PNG." },
        502,
      );
    }

    let suggestions = parseSuggestionsJson(raw);
    if (suggestions.length < 5) {
      console.warn("[modelo-sugerir-melhorias] short list:", suggestions.length, raw.slice(0, 200));
      return jsonResponse(
        { success: false, error: "Sugestões incompletas. Tente novamente." },
        502,
      );
    }

    suggestions = suggestions.slice(0, 5);

    return jsonResponse({ suggestions });
  } catch (error) {
    console.error("[modelo-sugerir-melhorias] Erro:", error);
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
      },
      500,
    );
  }
});
