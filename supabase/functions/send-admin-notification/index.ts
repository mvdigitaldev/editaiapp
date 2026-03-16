import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type TargetType = "all" | "plan" | "user";
type PlanFilter = "free" | "basic" | "pro";

interface RequestBody {
  title: string;
  body: string;
  data?: Record<string, unknown>;
  targetType: TargetType;
  planFilter?: PlanFilter;
  userId?: string;
}

interface DeviceTokenRow {
  token: string;
  platform: string;
}

// FCM: converter data para strings (requisito do Firebase)
function convertDataToStrings(data: Record<string, unknown>): Record<string, string> {
  const converted: Record<string, string> = {};
  for (const [key, value] of Object.entries(data ?? {})) {
    if (value === null || value === undefined) {
      converted[key] = "";
    } else if (typeof value === "boolean") {
      converted[key] = value ? "true" : "false";
    } else if (typeof value === "number") {
      converted[key] = value.toString();
    } else if (typeof value === "object") {
      converted[key] = JSON.stringify(value);
    } else {
      converted[key] = String(value);
    }
  }
  return converted;
}

async function createSignedJwt(serviceAccount: {
  client_email: string;
  token_uri: string;
  private_key: string;
}) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };
  const base64UrlEncode = (str: string) =>
    btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  const header = { alg: "RS256", typ: "JWT" };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const privateKeyData = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(privateKeyData), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`)
  );
  const encodedSignature = base64UrlEncode(String.fromCharCode(...new Uint8Array(signature)));
  return `${encodedHeader}.${encodedPayload}.${encodedSignature}`;
}

async function getAccessToken(serviceAccount: {
  client_email: string;
  token_uri: string;
  private_key: string;
}) {
  const signedJwt = await createSignedJwt(serviceAccount);
  const res = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedJwt,
    }),
  });
  if (!res.ok) throw new Error(`Erro ao obter access token: ${await res.text()}`);
  const data = await res.json();
  return data.access_token;
}

async function sendFCMNotification(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
) {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
      },
    }),
  });
  if (!res.ok) {
    const err = await res.json();
    throw new Error(JSON.stringify(err));
  }
  return res.json();
}

async function getPlanIdsByFilter(
  supabase: ReturnType<typeof createClient>,
  planFilter: PlanFilter
): Promise<string[]> {
  const names = {
    free: ["Free"],
    basic: ["Basic"],
    pro: ["PRO"],
  }[planFilter] ?? [];
  for (const name of names) {
    const { data, error } = await supabase.from("plans").select("id").eq("name", name);
    if (!error && data?.length) return data.map((r) => r.id);
  }
  return [];
}

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };

  if (req.method === "OPTIONS") return new Response(null, { status: 200, headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Método não permitido" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!firebaseJson) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON não configurado");
    }
    const serviceAccount = JSON.parse(firebaseJson);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Configuração do Supabase não encontrada");
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const body = (await req.json()) as RequestBody;
    const { title, body: messageBody, targetType, planFilter, userId } = body;

    if (!title?.trim() || !messageBody?.trim()) {
      return new Response(
        JSON.stringify({ error: "title e body são obrigatórios" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let tokens: DeviceTokenRow[] = [];
    let usersCount = 0;

    if (targetType === "user" && userId) {
      const { data, error } = await supabase
        .from("device_tokens")
        .select("token, platform")
        .eq("user_id", userId);
      if (error) throw new Error(`Erro ao buscar tokens: ${error.message}`);
      tokens = (data ?? []) as DeviceTokenRow[];
      usersCount = 1;
    } else if (targetType === "all") {
      const { data, error } = await supabase
        .from("device_tokens")
        .select("token, platform");
      if (error) throw new Error(`Erro ao buscar tokens: ${error.message}`);
      tokens = (data ?? []) as DeviceTokenRow[];
      usersCount = tokens.length;
    } else if (targetType === "plan" && planFilter) {
      const planIds = await getPlanIdsByFilter(supabase, planFilter);
      if (planIds.length === 0) {
        return new Response(
          JSON.stringify({
            count: 0,
            message: "Nenhum plano encontrado para o filtro selecionado.",
            usersCount: 0,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      // EditAI: users.current_plan_id em vez de user_plans
      const { data: planUsers, error: planError } = await supabase
        .from("users")
        .select("id")
        .in("current_plan_id", planIds);
      if (planError) throw new Error(`Erro ao buscar usuários do plano: ${planError.message}`);
      const userIds = [...new Set((planUsers ?? []).map((r) => r.id))];
      usersCount = userIds.length;

      if (userIds.length === 0) {
        return new Response(
          JSON.stringify({
            count: 0,
            message: "Nenhum usuário encontrado para o plano selecionado.",
            usersCount: 0,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: rpcData, error: rpcError } = await supabase.rpc("get_device_tokens_for_users", {
        user_ids: userIds,
      });
      if (!rpcError && rpcData && Array.isArray(rpcData)) {
        tokens = rpcData as DeviceTokenRow[];
      }
    }

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({
          count: 0,
          message:
            "Nenhum device token encontrado para os usuários selecionados. Os usuários precisam ter o app instalado e permitido notificações.",
          usersCount,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const accessToken = await getAccessToken(serviceAccount);
    const dataAsStrings = convertDataToStrings(body.data ?? {});

    const results = await Promise.allSettled(
      tokens.map((t) =>
        sendFCMNotification(
          accessToken,
          serviceAccount.project_id,
          t.token,
          title.trim(),
          messageBody.trim(),
          dataAsStrings
        )
      )
    );

    const successCount = results.filter((r) => r.status === "fulfilled").length;

    return new Response(
      JSON.stringify({
        count: successCount,
        message: `${successCount} notificação(ões) enviada(s) com sucesso.`,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erro interno";
    console.error("Erro send-admin-notification:", err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
