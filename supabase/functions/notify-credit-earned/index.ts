import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const FCM_TOKEN_URL = "https://oauth2.googleapis.com/token";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

interface NotifyPayload {
  user_id: string;
  amount: number;
  type: string;
  description?: string;
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64UrlEncode(data: Uint8Array | string): string {
  let str: string;
  if (typeof data === "string") {
    str = data;
  } else {
    let binary = "";
    for (let i = 0; i < data.length; i++) {
      binary += String.fromCharCode(data[i]);
    }
    str = binary;
  }
  const base64 = btoa(str);
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function createGoogleJwt(sa: ServiceAccount): Promise<string> {
  const key = await importPrivateKey(sa.private_key);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: FCM_TOKEN_URL,
    iat: now,
    exp: now + 3600,
    scope: FCM_SCOPE,
  };
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${headerB64}.${payloadB64}`;
  const signatureInputBytes = new TextEncoder().encode(signatureInput);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    signatureInputBytes,
  );
  const signatureB64 = base64UrlEncode(new Uint8Array(signature));
  return `${signatureInput}.${signatureB64}`;
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const jwt = await createGoogleJwt(sa);
  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: jwt,
  });
  const res = await fetch(FCM_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OAuth2 token failed: ${res.status} ${text}`);
  }
  const data = (await res.json()) as { access_token: string };
  return data.access_token;
}

function buildNotificationBody(amount: number, type: string): { title: string; body: string } {
  const title = "Você ganhou créditos";
  const amountStr = amount === 1 ? "1 crédito" : `${amount} créditos`;
  let body: string;
  if (type === "subscription_credit") {
    body = `Seu plano adicionou ${amountStr} na sua conta.`;
  } else if (type === "extra_purchase" || type === "bonus") {
    body = `Você recebeu ${amountStr} extras. Aproveite para editar mais fotos!`;
  } else {
    body = `Você recebeu ${amountStr} na sua conta.`;
  }
  return { title, body };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Método não permitido" }, 405);
  }

  const invocationSecret = Deno.env.get("NOTIFY_CREDITS_INVOCATION_SECRET");
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!invocationSecret || token !== invocationSecret) {
    return jsonResponse({ success: false, error: "Não autorizado" }, 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[notify-credit-earned] SUPABASE_URL ou SERVICE_ROLE_KEY ausente");
      return jsonResponse(
        { success: false, error: "Configuração do Supabase ausente" },
        500,
      );
    }

    if (!saJson || saJson.trim() === "") {
      console.error("[notify-credit-earned] FIREBASE_SERVICE_ACCOUNT_JSON ausente");
      return jsonResponse(
        { success: false, error: "Firebase não configurado" },
        500,
      );
    }

    let payload: NotifyPayload;
    try {
      payload = (await req.json()) as NotifyPayload;
    } catch {
      return jsonResponse({ success: false, error: "JSON inválido" }, 400);
    }

    const { user_id, amount, type } = payload;
    if (!user_id || amount == null || amount <= 0) {
      return jsonResponse(
        { success: false, error: "user_id e amount positivo são obrigatórios" },
        400,
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: tokens, error: tokensError } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", user_id);

    if (tokensError) {
      console.error("[notify-credit-earned] Erro ao buscar tokens:", tokensError);
      return jsonResponse(
        { success: false, error: "Erro ao buscar dispositivos" },
        500,
      );
    }

    if (!tokens || tokens.length === 0) {
      return jsonResponse({ success: true, sent: 0, message: "Sem dispositivos" });
    }

    const sa = JSON.parse(saJson) as ServiceAccount;
    const projectId = sa.project_id || "";
    if (!projectId) {
      return jsonResponse(
        { success: false, error: "project_id ausente no service account" },
        500,
      );
    }

    const accessToken = await getAccessToken(sa);
    const { title, body } = buildNotificationBody(amount, type || "");
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let sent = 0;
    const invalidTokens: string[] = [];

    for (const row of tokens) {
      const token = (row as { token: string }).token;
      if (!token) continue;

      const fcmBody = {
        message: {
          token,
          notification: { title, body },
          data: { deep_link: "/credits-shop" },
          android: {
            priority: "high",
            notification: { channel_id: "editaiapp_notifications" },
          },
          apns: {
            payload: { aps: { sound: "default" } },
            fcm_options: {},
          },
        },
      };

      const fcmRes = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(fcmBody),
      });

      if (fcmRes.ok) {
        sent++;
      } else {
        const errText = await fcmRes.text();
        console.warn("[notify-credit-earned] FCM falhou para um token:", fcmRes.status, errText);
        if (fcmRes.status === 404 || fcmRes.status === 400) {
          try {
            const err = JSON.parse(errText);
            const code = err?.error?.details?.[0]?.errorCode || err?.error?.message || "";
            if (
              code.includes("UNREGISTERED") ||
              code.includes("NOT_FOUND") ||
              code.includes("INVALID_ARGUMENT")
            ) {
              invalidTokens.push(token);
            }
          } catch (_) {
            /* ignore */
          }
        }
      }
    }

    if (invalidTokens.length > 0) {
      try {
        await supabase
          .from("device_tokens")
          .delete()
          .in("token", invalidTokens);
      } catch (e) {
        console.warn("[notify-credit-earned] Erro ao remover tokens inválidos:", e);
      }
    }

    return jsonResponse({ success: true, sent, invalid_removed: invalidTokens.length });
  } catch (error) {
    console.error("[notify-credit-earned] Erro inesperado:", error);
    return jsonResponse(
      { success: false, error: "Erro interno ao enviar notificação" },
      500,
    );
  }
});
