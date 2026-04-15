import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const FCM_TOKEN_URL = "https://oauth2.googleapis.com/token";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

interface NotifyRequestBody {
  notification_id: string;
}

interface EditNotificationRow {
  id: string;
  edit_id: string;
  user_id: string;
  terminal_status: "completed" | "failed";
  route: string;
  delivery_status: "pending" | "sending" | "sent" | "failed";
  attempt_count: number;
}

interface ClaimableEditNotificationRow extends EditNotificationRow {
  last_error?: string | null;
  sent_at?: string | null;
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
  const binaryDer = Uint8Array.from(
    atob(pemContents),
    (c) => c.charCodeAt(0),
  );
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

function buildNotificationCopy(status: "completed" | "failed") {
  if (status === "completed") {
    return {
      title: "Sua edição ficou pronta",
      body: "Toque para ver o resultado.",
    };
  }

  return {
    title: "Sua edição não foi concluída",
    body: "Toque para ver os detalhes e acompanhar o status.",
  };
}

async function claimNotification(
  supabase: ReturnType<typeof createClient>,
  notification: EditNotificationRow,
): Promise<ClaimableEditNotificationRow | null> {
  const { data, error } = await supabase
    .from("edit_notifications")
    .update({
      delivery_status: "sending",
      attempt_count: notification.attempt_count + 1,
      last_error: null,
    })
    .eq("id", notification.id)
    .in("delivery_status", ["pending", "failed"])
    .is("sent_at", null)
    .select(
      "id, edit_id, user_id, terminal_status, route, delivery_status, attempt_count, last_error, sent_at",
    )
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return (data as ClaimableEditNotificationRow | null) ?? null;
}

async function sendPush(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<Response> {
  const fcmUrl =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  return await fetch(fcmUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          priority: "high",
          notification: { channel_id: "editaiapp_notifications" },
        },
        apns: {
          payload: { aps: { sound: "default" } },
          fcm_options: {},
        },
      },
    }),
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Método não permitido" }, 405);
  }

  const invocationSecret =
    Deno.env.get("NOTIFY_EDIT_TERMINAL_INVOCATION_SECRET") ||
    Deno.env.get("NOTIFY_CREDITS_INVOCATION_SECRET");
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : null;
  if (!invocationSecret || token == null || token !== invocationSecret.trim()) {
    return jsonResponse({ success: false, error: "Não autorizado" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!supabaseUrl || !serviceRoleKey || !saJson) {
    return jsonResponse(
      { success: false, error: "Configuração do serviço indisponível" },
      500,
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  let notificationId = "";

  try {
    const payload = (await req.json()) as Partial<NotifyRequestBody>;
    notificationId =
      typeof payload.notification_id === "string"
        ? payload.notification_id.trim()
        : "";
    if (!notificationId) {
      return jsonResponse(
        { success: false, error: "notification_id é obrigatório" },
        400,
      );
    }

    const { data: row, error } = await supabase
      .from("edit_notifications")
      .select(
        "id, edit_id, user_id, terminal_status, route, delivery_status, attempt_count",
      )
      .eq("id", notificationId)
      .maybeSingle();

    if (error) {
      throw new Error(error.message);
    }

    const notification = row as EditNotificationRow | null;
    if (!notification) {
      return jsonResponse({ success: true, skipped: "not_found" }, 202);
    }

    if (notification.delivery_status === "sent") {
      return jsonResponse({ success: true, skipped: "already_sent" });
    }

    const claimedNotification = await claimNotification(supabase, notification);
    if (!claimedNotification) {
      const { data: currentRow, error: currentError } = await supabase
        .from("edit_notifications")
        .select(
          "id, edit_id, user_id, terminal_status, route, delivery_status, attempt_count",
        )
        .eq("id", notification.id)
        .maybeSingle();

      if (currentError) {
        throw new Error(currentError.message);
      }

      const currentNotification = currentRow as EditNotificationRow | null;
      if (currentNotification?.delivery_status === "sent") {
        return jsonResponse({ success: true, skipped: "already_sent" });
      }

      return jsonResponse({ success: true, skipped: "already_claimed" }, 202);
    }

    const { data: tokens, error: tokenError } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", claimedNotification.user_id);

    if (tokenError) {
      throw new Error(tokenError.message);
    }

    const deviceTokens = (tokens ?? [])
      .map((item) => (item as { token?: string }).token ?? "")
      .filter((value) => value.length > 0);

    if (deviceTokens.length === 0) {
      await supabase
        .from("edit_notifications")
        .update({
          delivery_status: "sent",
          sent_at: new Date().toISOString(),
          last_error: null,
        })
        .eq("id", claimedNotification.id);

      return jsonResponse({ success: true, sent: 0, skipped: "no_devices" });
    }

    const serviceAccount = JSON.parse(saJson) as ServiceAccount;
    const projectId = serviceAccount.project_id ?? "";
    if (!projectId) {
      throw new Error("project_id ausente no service account");
    }

    const accessToken = await getAccessToken(serviceAccount);
    const { title, body } = buildNotificationCopy(
      claimedNotification.terminal_status,
    );
    const data = {
      type: "edit_terminal",
      route: claimedNotification.route,
      deep_link: claimedNotification.route,
      edit_id: claimedNotification.edit_id,
      status: claimedNotification.terminal_status,
    };

    const invalidTokens: string[] = [];
    let sent = 0;

    for (const deviceToken of deviceTokens) {
      const response = await sendPush(
        accessToken,
        projectId,
        deviceToken,
        title,
        body,
        data,
      );

      if (response.ok) {
        sent++;
        continue;
      }

      const errorText = await response.text();
      if (response.status === 400 || response.status === 404) {
        try {
          const parsed = JSON.parse(errorText);
          const code = parsed?.error?.details?.[0]?.errorCode ||
            parsed?.error?.message ||
            "";
          if (
            code.includes("UNREGISTERED") ||
            code.includes("NOT_FOUND") ||
            code.includes("INVALID_ARGUMENT")
          ) {
            invalidTokens.push(deviceToken);
            continue;
          }
        } catch {
          // noop
        }
      }

      throw new Error(`FCM send failed: ${response.status} ${errorText}`);
    }

    if (invalidTokens.length > 0) {
      await supabase.from("device_tokens").delete().in("token", invalidTokens);
    }

    await supabase
      .from("edit_notifications")
      .update({
        delivery_status: "sent",
        sent_at: new Date().toISOString(),
        last_error: null,
      })
      .eq("id", claimedNotification.id);

    return jsonResponse({
      success: true,
      sent,
      invalid_removed: invalidTokens.length,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[notify-edit-terminal] Erro:", message);
    if (notificationId) {
      await supabase
        .from("edit_notifications")
        .update({
          delivery_status: "failed",
          last_error: message,
        })
        .eq("id", notificationId);
    }
    return jsonResponse({ success: false, error: message }, 500);
  }
});
