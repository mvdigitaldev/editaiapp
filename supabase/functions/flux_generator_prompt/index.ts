import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
import {
  EDIT_PROMPT_OPTIMIZER_SYSTEM,
  INTENT_CLASSIFIER_SYSTEM_SINGLE,
  MINIMAL_EDIT_PROMPT_SYSTEM,
  buildMinimalEditUserMessage,
  buildOptimizerUserMessage,
  ensureSubjectPreservation,
} from "../_shared/flux_prompt_optimizer.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ✅ AGORA ACEITA image_context
    const { user_prompt, image_context } = await req.json();
    if (!user_prompt) throw new Error("Missing user_prompt");

    const authHeader = req.headers.get("Authorization");
    const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

    let user_id: string | null = null;
    if (authHeader?.startsWith("Bearer ")) {
      const authClient = createClient(SUPABASE_URL!, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: { user } } = await authClient.auth.getUser();
      user_id = user?.id ?? null;
    }

    // =========================
    // 1️⃣ TRANSLATE TO ENGLISH
    // =========================

    const translateResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0,
        messages: [
          {
            role: "system",
            content: "Translate the user request to English. Output only the translated text."
          },
          { role: "user", content: user_prompt }
        ]
      })
    });

    const translateData = await translateResponse.json();
    const translated_prompt = translateData.choices[0].message.content.trim();

    // =========================
    // 2️⃣ INTENT CLASSIFICATION
    // =========================

    const intentResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0,
        messages: [
          {
            role: "system",
            content: INTENT_CLASSIFIER_SYSTEM_SINGLE,
          },
          { role: "user", content: translated_prompt }
        ]
      })
    });

    const intentData = await intentResponse.json();
    const intent = intentData.choices[0].message.content.trim();

    // =========================
    // 3️⃣ QUERY EXPANSION (AGORA USA CONTEXTO DA IMAGEM)
    // =========================

    const expanded_query = `
User editing request:
${translated_prompt}

Image context:
${image_context || "Unknown image context."}

Intent category: ${intent}

Focus on relevant FLUX official documentation, especially:
- intentional subject/color preservation when relocating products
- replacement strategy for negative prompts
- structured prompting
- subject + action + style + context
`;

    // =========================
    // 4️⃣ EMBEDDING
    // =========================

    const embeddingResponse = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        input: expanded_query,
        model: "text-embedding-3-small",
      }),
    });

    const embeddingData = await embeddingResponse.json();

    if (!embeddingData.data || !embeddingData.data[0]?.embedding) {
      throw new Error("Embedding generation failed");
    }

    const query_embedding = embeddingData.data[0].embedding;

    // =========================
    // 5️⃣ RAG MATCH (threshold corrigido)
    // =========================

    const { data: matchedDocs, error: rpcError } =
      await supabase.rpc("match_flux_docs", {
        query_embedding,
        match_threshold: 0.35,
        match_count: 8,
      });

    if (rpcError) throw new Error(`RPC Error: ${rpcError.message}`);

    const match_count_returned = matchedDocs?.length || 0;

    const contextString =
      matchedDocs?.length > 0
        ? matchedDocs.map((doc: any) => doc.content).join("\n\n---\n\n").slice(0, 4000)
        : "";

    const avg_similarity =
      matchedDocs?.length > 0
        ? matchedDocs.reduce((acc: number, doc: any) => acc + doc.similarity, 0) / matchedDocs.length
        : 0;

    const matched_ids = matchedDocs?.map((doc: any) => doc.id) || [];

    // =========================
    // 6️⃣ FINAL PROMPT GENERATION (AGORA COM CONTEXTO REAL)
    // =========================

    let improved_prompt: string;

    // Bypass: quando RAG retorna docs irrelevantes e o pedido é curto, usar prompt minimal
    if (avg_similarity < 0.5 && translated_prompt.split(/\s+/).length <= 15) {
      const minimalResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0,
          messages: [
            {
              role: "system",
              content: MINIMAL_EDIT_PROMPT_SYSTEM,
            },
            {
              role: "user",
              content: buildMinimalEditUserMessage(translated_prompt, image_context),
            },
          ],
        }),
      });
      const minimalData = await minimalResponse.json();
      improved_prompt = minimalData.choices?.[0]?.message?.content?.trim() || translated_prompt;
    } else {
      const chatResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0,
          messages: [
            {
              role: "system",
              content: EDIT_PROMPT_OPTIMIZER_SYSTEM,
            },
            {
              role: "user",
              content: buildOptimizerUserMessage({
                translated: translated_prompt,
                imageContext: image_context,
                intent,
                contextString,
              }),
            },
          ],
        }),
      });

      const chatData = await chatResponse.json();

      if (!chatData.choices || !chatData.choices[0]?.message?.content) {
        throw new Error("Chat completion failed");
      }

      improved_prompt = chatData.choices[0].message.content.trim();
    }

    improved_prompt = ensureSubjectPreservation(improved_prompt || translated_prompt, {
      intent,
      imageContext: image_context,
      translatedUserPrompt: translated_prompt,
    });

    // =========================
    // 7️⃣ LOGGING
    // =========================

    await supabase.from("prompt_optimization_logs").insert({
      user_id,
      original_prompt: user_prompt,
      improved_prompt,
      avg_similarity,
      matched_chunk_ids: matched_ids,
      metadata: {
        model: "gpt-4o-mini",
        source: "flutter_app",
        rag_match_count: match_count_returned,
        intent,
        image_context_used: !!image_context
      },
    });

    return new Response(
      JSON.stringify({
        original_prompt: user_prompt,
        improved_prompt,
        intent,
        rag_match_count: match_count_returned,
        avg_similarity
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }
});