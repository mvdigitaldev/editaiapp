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

interface SupportNotificationRow {
  id: string;
  ticket_id: string;
  message_id?: string | null;
  recipient_user_id: string;
  actor_user_id?: string | null;
  kind: "new_ticket" | "admin_reply";
  route: string;
  delivery_status: "pending" | "sending" | "sent" | "failed";
  attempt_count: number;
}

interface ClaimableSupportNotificationRow extends SupportNotificationRow {
  last_error?: string | null;
  sent_at?: string | null;
}

interface TicketRow {
  id: string;
  subject?: string | null;
  user_id: string;
  owner?: {
    name?: string | null;
    email?: string | null;
  } | null;
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
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signatureInput),
  );
  return `${signatureInput}.${base64UrlEncode(new Uint8Array(signature))}`;
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
    throw new Error(`OAuth2 token failed: ${res.status} ${await res.text()}`);
  }
  const data = (await res.json()) as { access_token: string };
  return data.access_token;
}

function buildNotificationCopy(
  kind: "new_ticket" | "admin_reply",
  ticket: TicketRow,
) {
  const ownerName = ticket.owner?.name?.trim() || ticket.owner?.email?.trim() || "usuario";
  const subject = ticket.subject?.trim() || "Novo chamado";

  if (kind === "new_ticket") {
    return {
      title: "Novo chamado aberto",
      body: `${ownerName}: ${subject}`,
    };
  }

  return {
    title: "Seu chamado foi respondido",
    body: subject,
  };
}

async function claimNotification(
  supabase: ReturnType<typeof createClient>,
  notification: SupportNotificationRow,
): Promise<ClaimableSupportNotificationRow | null> {
  const { data, error } = await supabase
    .from("support_notifications")
    .update({
      delivery_status: "sending",
      attempt_count: notification.attempt_count + 1,
      last_error: null,
    })
    .eq("id", notification.id)
    .in("delivery_status", ["pending", "failed"])
    .is("sent_at", null)
    .select(
      "id, ticket_id, message_id, recipient_user_id, actor_user_id, kind, route, delivery_status, attempt_count, last_error, sent_at",
    )
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return (data as ClaimableSupportNotificationRow | null) ?? null;
}

async function sendPush(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  return await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
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
    },
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo nao permitido" }, 405);
  }

  const invocationSecret =
    Deno.env.get("NOTIFY_SUPPORT_TICKET_INVOCATION_SECRET") ||
    Deno.env.get("NOTIFY_EDIT_TERMINAL_INVOCATION_SECRET");
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : null;

  if (!invocationSecret || token == null || token !== invocationSecret.trim()) {
    return jsonResponse({ success: false, error: "Nao autorizado" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!supabaseUrl || !serviceRoleKey || !saJson) {
    return jsonResponse(
      { success: false, error: "Configuracao do servico indisponivel" },
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
        { success: false, error: "notification_id e obrigatorio" },
        400,
      );
    }

    const { data: row, error } = await supabase
      .from("support_notifications")
      .select(
        "id, ticket_id, message_id, recipient_user_id, actor_user_id, kind, route, delivery_status, attempt_count",
      )
      .eq("id", notificationId)
      .maybeSingle();

    if (error) {
      throw new Error(error.message);
    }

    const notification = row as SupportNotificationRow | null;
    if (!notification) {
      return jsonResponse({ success: true, skipped: "not_found" }, 202);
    }

    if (notification.delivery_status === "sent") {
      return jsonResponse({ success: true, skipped: "already_sent" });
    }

    const claimedNotification = await claimNotification(supabase, notification);
    if (!claimedNotification) {
      return jsonResponse({ success: true, skipped: "already_claimed" }, 202);
    }

    const { data: tokens, error: tokenError } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", claimedNotification.recipient_user_id);

    if (tokenError) {
      throw new Error(tokenError.message);
    }

    const deviceTokens = (tokens ?? [])
      .map((item) => (item as { token?: string }).token ?? "")
      .filter((item) => item.length > 0);

    const { data: ticketRow, error: ticketError } = await supabase
      .from("support_tickets")
      .select("id, subject, user_id, owner:users!support_tickets_user_id_fkey(name, email)")
      .eq("id", claimedNotification.ticket_id)
      .maybeSingle();

    if (ticketError) {
      throw new Error(ticketError.message);
    }

    const ticket = ticketRow as TicketRow | null;
    if (!ticket) {
      await supabase
        .from("support_notifications")
        .update({
          delivery_status: "sent",
          sent_at: new Date().toISOString(),
          last_error: null,
        })
        .eq("id", claimedNotification.id);

      return jsonResponse({ success: true, sent: 0, skipped: "ticket_not_found" });
    }

    if (deviceTokens.length === 0) {
      await supabase
        .from("support_notifications")
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
    const { title, body } = buildNotificationCopy(claimedNotification.kind, ticket);
    const data = {
      type: "support_ticket",
      route: claimedNotification.route,
      deep_link: claimedNotification.route,
      ticket_id: claimedNotification.ticket_id,
      notification_kind: claimedNotification.kind,
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
      .from("support_notifications")
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
    console.error("[notify-support-ticket] Erro:", message);
    if (notificationId) {
      await supabase
        .from("support_notifications")
        .update({
          delivery_status: "failed",
          last_error: message,
        })
        .eq("id", notificationId);
    }
    return jsonResponse({ success: false, error: message }, 500);
  }
});
