import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { getExpirationDays } from "./plan_limits.ts";

export interface EditImageMetadata {
  file_size?: number;
  mime_type?: string;
  width?: number;
  height?: number;
}

interface CreateEditAndReserveOptions {
  imageId?: string | null;
  imageMetadata?: EditImageMetadata;
  promptTextOriginal?: string | null;
  clientRequestId?: string | null;
}

interface ExistingEditLookup {
  id: string;
  task_id: string | null;
  status: string;
  created_at: string;
}

export interface CreateEditAndReserveResult {
  editId: string;
  reservationId: string;
  acceptedAt: string;
  status: string;
  taskId: string | null;
  reused: boolean;
}

const DEFAULT_RESERVATION_TTL_SECONDS = 6 * 60 * 60;

interface CreditReservationLookup {
  id: string;
  status: "pending" | "consumed" | "released" | "expired";
}

async function findEditByClientRequestId(
  supabase: SupabaseClient,
  userId: string,
  clientRequestId: string,
): Promise<ExistingEditLookup | null> {
  const { data, error } = await supabase
    .from("edits")
    .select("id, task_id, status, created_at")
    .eq("user_id", userId)
    .eq("client_request_id", clientRequestId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return (data as ExistingEditLookup | null) ?? null;
}

async function buildReusedEditResult(
  supabase: SupabaseClient,
  existing: ExistingEditLookup,
): Promise<CreateEditAndReserveResult> {
  const reservation = await getLatestReservationForEdit(supabase, existing.id);
  return {
    editId: existing.id,
    reservationId: reservation?.id ?? "",
    acceptedAt: existing.created_at,
    status: existing.status || "queued",
    taskId: existing.task_id ?? null,
    reused: true,
  };
}

export async function createEditAndReserveCredits(
  supabase: SupabaseClient,
  userId: string,
  operationType: string,
  credits: number,
  promptText: string,
  taskId: string | null,
  options?: CreateEditAndReserveOptions,
): Promise<CreateEditAndReserveResult> {
  let metadata: EditImageMetadata | undefined = options?.imageMetadata;
  const clientRequestId =
    typeof options?.clientRequestId === "string" &&
        options.clientRequestId.trim().length > 0
      ? options.clientRequestId.trim()
      : null;

  if (clientRequestId) {
    const existing = await findEditByClientRequestId(
      supabase,
      userId,
      clientRequestId,
    );
    if (existing) {
      return await buildReusedEditResult(supabase, existing);
    }
  }

  if (options?.imageId && !metadata) {
    const { data: img } = await supabase
      .from("images")
      .select("file_size, mime_type, width, height")
      .eq("id", options.imageId)
      .single();
    if (img) {
      metadata = {
        file_size: img.file_size ?? undefined,
        mime_type: img.mime_type ?? undefined,
        width: img.width ?? undefined,
        height: img.height ?? undefined,
      };
    }
  }

  const expirationDays = await getExpirationDays(supabase, userId);
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + expirationDays);

  const insertPayload: Record<string, unknown> = {
    user_id: userId,
    image_id: options?.imageId ?? null,
    prompt_text: promptText,
    prompt_text_original: options?.promptTextOriginal ?? promptText,
    operation_type: operationType,
    task_id: taskId,
    status: "queued",
    credits_used: credits,
    expires_at: expiresAt.toISOString(),
    client_request_id: clientRequestId,
  };
  if (metadata?.file_size != null) insertPayload.file_size = metadata.file_size;
  if (metadata?.mime_type) insertPayload.mime_type = metadata.mime_type;
  if (metadata?.width != null) insertPayload.width = metadata.width;
  if (metadata?.height != null) insertPayload.height = metadata.height;

  const { data: edit, error: editErr } = await supabase
    .from("edits")
    .insert(insertPayload as Record<string, unknown>)
    .select("id, created_at")
    .single();

  if (editErr || !edit?.id) {
    if (
      clientRequestId &&
      editErr?.message?.toLowerCase().includes("duplicate key")
    ) {
      const existing = await findEditByClientRequestId(
        supabase,
        userId,
        clientRequestId,
      );
      if (existing) {
        return await buildReusedEditResult(supabase, existing);
      }
    }
    throw new Error(editErr?.message ?? "Falha ao criar registro de edição");
  }

  const { data: reservationId, error: reserveErr } = await supabase.rpc(
    "reserve_credits_for_operation",
    {
      p_user_id: userId,
      p_credits: credits,
      p_operation_type: operationType,
      p_edit_id: edit.id,
      p_ttl_seconds: DEFAULT_RESERVATION_TTL_SECONDS,
    },
  );

  if (reserveErr || !reservationId) {
    await supabase.from("edits").delete().eq("id", edit.id);
    if (reserveErr?.message?.includes("insufficient_credits")) {
      const e = new Error("Créditos insuficientes") as Error & {
        status?: number;
      };
      e.status = 402;
      throw e;
    }
    throw new Error(reserveErr?.message ?? "Falha ao reservar créditos");
  }

  return {
    editId: edit.id,
    reservationId,
    acceptedAt: edit.created_at as string,
    status: "queued",
    taskId,
    reused: false,
  };
}

export async function consumeReservedCredits(
  supabase: SupabaseClient,
  reservationId: string,
  referenceId: string,
  description = "usage",
): Promise<void> {
  const { error } = await supabase.rpc("consume_reserved_credits", {
    p_reservation_id: reservationId,
    p_reference_id: referenceId,
    p_description: description,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function releaseReservedCredits(
  supabase: SupabaseClient,
  reservationId: string,
  reason?: string,
): Promise<boolean> {
  const id = typeof reservationId === "string" ? reservationId.trim() : "";
  if (!id) {
    console.warn("[credits] release_reserved: empty reservation id");
    return false;
  }
  const { error } = await supabase.rpc("release_credit_reservation", {
    p_reservation_id: id,
    p_reason: reason ?? null,
  });
  if (error) {
    console.error(
      "[credits] release_reserved failed",
      id,
      reason,
      error.message,
    );
    return false;
  }
  return true;
}

export async function getLatestReservationForEdit(
  supabase: SupabaseClient,
  editId: string,
): Promise<CreditReservationLookup | null> {
  const { data, error } = await supabase
    .from("credit_reservations")
    .select("id, status")
    .eq("edit_id", editId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return data as CreditReservationLookup | null;
}

export async function consumeReservedCreditsForEdit(
  supabase: SupabaseClient,
  editId: string,
  description = "usage",
): Promise<void> {
  const reservation = await getLatestReservationForEdit(supabase, editId);
  if (!reservation) return;
  await consumeReservedCredits(supabase, reservation.id, editId, description);
}

export async function releaseReservedCreditsForEdit(
  supabase: SupabaseClient,
  editId: string,
  reason?: string,
): Promise<boolean> {
  const reservation = await getLatestReservationForEdit(supabase, editId);
  if (!reservation || reservation.status !== "pending") return true;
  const ok = await releaseReservedCredits(supabase, reservation.id, reason);
  if (ok) return true;
  await new Promise((r) => setTimeout(r, 250));
  const retry = await releaseReservedCredits(supabase, reservation.id, reason);
  if (!retry) {
    console.error(
      "[credits] release_reserved_for_edit retry failed",
      editId,
      reason,
    );
  }
  return retry;
}
