/**
 * FLUX edit prompt rules aligned with Black Forest Labs prompting guides:
 * - Describe the change, not a full new scene
 * - Preserve identity/color intentionally when the user does not ask to change them
 * - Prefer positive replacement language (no negative prompts)
 * - Never name brands/trademarks/logos (BFL often returns REQUEST MODERATED)
 */

export const IMAGE_CONTEXT_VISION_PROMPT =
  `Describe this image in 1-2 sentences in English for product/subject editing.
Focus on: main subject type (speaker, bottle, shirt, etc.), its exact colors (specific hues), materials/textures, and the current setting.
Do NOT mention brand names, trademarks, model names, or logo text (e.g. never write JBL, Nike, Apple).
If a logo is visible, say only "existing logo markings" without naming the brand.
Output only the description, no preamble.`;

export const INTENT_CATEGORIES_SINGLE = [
  "subject_removal",
  "lighting_adjustment",
  "color_grading",
  "typography",
  "composition",
  "scene_change",
  "general_edit",
] as const;

export const INTENT_CATEGORIES_MULTI = [
  "multi_reference_composite",
  "subject_removal",
  "lighting_adjustment",
  "color_grading",
  "typography",
  "composition",
  "scene_change",
  "general_edit",
] as const;

const COLOR_CHANGE_RE =
  /\b(change|recolor|recolour|paint|dye|tint|switch|alter|modify)\b[\w\s,]{0,40}\b(color|colour|hue|shade|tone)\b|\b(color|colour)\b[\w\s,]{0,24}\b(to|into|as)\b|\b(make|turn|paint)\b[\w\s,]{0,24}\b(it|them|the\s+\w+)\b[\w\s,]{0,16}\b(blue|red|green|yellow|black|white|pink|purple|orange|brown|gray|grey|gold|silver|teal|navy)\b/i;

const PRESERVE_ALREADY_RE =
  /\b(keep|keeping|maintain|maintaining|preserve|preserving|same|exact|original)\b[\w\s,]{0,40}\b(color|colour|appearance|look|identity|shape|product|subject|markings)\b|\bsame\s+(exact\s+)?(original\s+)?(colors?|colours?|appearance|look)\b/i;

const SCENE_CHANGE_INTENTS = new Set([
  "scene_change",
  "composition",
  "general_edit",
  "multi_reference_composite",
]);

/** Common consumer brands that often trigger BFL request moderation when named in prompts. */
const BRAND_NAME_RE =
  /\b(?:jbl|sony|bose|samsung|apple|iphone|ipad|macbook|nike|adidas|puma|gucci|louis\s*vuitton|lv|chanel|prada|hermes|hermès|rolex|cartier|canon|nikon|gopro|dyson|nespresso|starbucks|coca[- ]?cola|pepsi|mcdonald'?s|burger\s*king|kfc|disney|marvel|pokemon|pokémon|lego|harley[- ]?davidson|ferrari|lamborghini|porsche|bmw|mercedes(?:-|\s*)benz|audi|toyota|honda|ford|tesla|xbox|playstation|nintendo|air\s*jordan|supreme|off[- ]?white|balenciaga|versace|fendi|dior|ysl|yves\s*saint\s*laurent|ray[- ]?ban|oakley|beats|skullcandy|logitech|razer|asus|lenovo|dell|hp|microsoft|google|pixel|xiaomi|huawei|oneplus|motorola|lg|panasonic|philips|sharp|toshiba|intel|amd|nvidia|qualcomm|android|ios|windows)\b/gi;

const LOGO_BRAND_PHRASE_RE =
  /\b(?:white|black|red|blue|silver|gold|colored)?\s*(?:brand\s+)?(?:logo|wordmark|trademark|brand\s+name)(?:\s+(?:text|markings?))?\b/gi;

export const INTENT_CLASSIFIER_SYSTEM_SINGLE = `Classify the editing intent into ONE of the following categories:
- subject_removal: remove or erase something
- lighting_adjustment: change lighting/exposure only
- color_grading: user explicitly wants to change colors/tones of the subject or scene
- typography: text edits
- composition: crop/framing/layout without relocating subject to a new environment
- scene_change: move/place subject into a new environment, background, room, outdoor setting, or lifestyle scene
- general_edit: other edits

Output only the category name.`;

export const INTENT_CLASSIFIER_SYSTEM_MULTI = `Classify the editing intent into ONE of the following categories:
- multi_reference_composite
- subject_removal
- lighting_adjustment
- color_grading
- typography
- composition
- scene_change
- general_edit
Output only the category name.`;

const NO_BRAND_RULE = `
BRAND / TRADEMARK SAFETY (critical — avoid REQUEST MODERATED):
- NEVER write brand names, trademarks, company names, or model names (e.g. JBL, Nike, Apple, iPhone).
- NEVER describe logo text by brand (bad: "white JBL logo"). Say only "keeping existing logo markings" if needed.
- Prefer generic product nouns: speaker, sneakers, phone, bag, bottle.`;

export const MINIMAL_EDIT_PROMPT_SYSTEM = `You optimize prompts for FLUX image EDITING (not text-to-image).

OUTPUT ONLY a short English edit instruction (15-45 words).

RULES (Black Forest Labs):
- Describe ONLY the requested change. Do NOT rewrite as a full scene caption.
- Prefer action form: "Place the same [subject] in [new setting]..." or "Change the background to..."
- ALWAYS preserve subject identity unless the user asked to change it: exact original colors, shape, materials, and appearance.
- If Image context lists subject colors, mention those colors explicitly (e.g. "the same blue speaker").
- NEVER use negative prompts ("don't", "without", "no..."). Use positive keep/maintain wording.
${NO_BRAND_RULE}
- Bad: "Speaker placed in a cozy indoor room setting." / "Place the same JBL speaker..."
- Good: "Place the same blue portable speaker in a cozy indoor living room, keeping its exact original color, shape, and appearance."`;

export const EDIT_PROMPT_OPTIMIZER_SYSTEM = `You are a FLUX image editing prompt optimizer (Black Forest Labs FLUX.2 / Kontext style).

STRICT RULES:
- OUTPUT ONLY the final improved English prompt.
- This is IMAGE EDITING: describe ONLY the change. The input image already provides the subject.
- Keep prompts SHORT (15-60 words) for simple edits.
- PRESERVE intentionally: unless the user explicitly asks to change the subject's color/appearance, ALWAYS include a keep clause such as "keeping its exact original colors, shape, materials, and appearance".
- When relocating a product/object/person to a new environment, name the subject generically and its key colors from Image context, then state the new setting.
- Do NOT turn the prompt into a generic scene caption that could regenerate the subject from scratch.
- NEVER use negative prompts. Use positive visual replacement ("replace the background with...", "place the same product in...").
- ONLY modify what the user requested.
${NO_BRAND_RULE}

Examples:
- User: place this speaker in a living room → "Place the same blue portable speaker in a cozy indoor living room on a side table, keeping its exact original blue color, shape, and appearance."
- User: beach setting, keep original color → "Change the background to a beach environment, keeping the subject in the same position with its exact original colors and appearance."`;

export const MULTI_REF_PROMPT_OPTIMIZER_SYSTEM = `You are a professional FLUX multi-reference image editing prompt optimizer.

STRICT RULES:
- OUTPUT ONLY the final improved English prompt.
- Combine reference images into one cohesive scene; describe how each input should be used.
- Keep prompts concise for simple requests.
- PRESERVE identity of products/clothing/people from references: exact original colors, materials, and appearance unless the user asks to change them.
- NEVER use negative prompts.
- Use positive visual replacement strategy.
- Follow: Subject + Action + Style + Context.
${NO_BRAND_RULE}`;

/** True when the user explicitly asks to change color/appearance. */
export function userRequestedColorChange(prompt: string): boolean {
  return COLOR_CHANGE_RE.test(prompt);
}

/** True when the prompt already asks to keep identity/color. */
export function alreadyPreservesIdentity(prompt: string): boolean {
  return PRESERVE_ALREADY_RE.test(prompt);
}

/**
 * Remove brand/trademark names that commonly trigger BFL REQUEST MODERATED.
 * Keeps generic product language; softens logo phrases.
 */
export function sanitizeBrandMentions(prompt: string): string {
  let out = prompt.replace(BRAND_NAME_RE, "").replace(LOGO_BRAND_PHRASE_RE, "existing logo markings");
  out = out
    .replace(/\s{2,}/g, " ")
    .replace(/\s+,/g, ",")
    .replace(/,\s*,/g, ",")
    .replace(/\s+\./g, ".")
    .replace(/\(\s*\)/g, "")
    .trim();
  return out;
}

/**
 * Safety net: append an explicit keep-clause when relocating/editing subjects
 * without a color-change request. Matches what works in direct BFL API tests.
 */
export function ensureSubjectPreservation(
  improvedPrompt: string,
  options: {
    intent?: string;
    imageContext?: string;
    translatedUserPrompt?: string;
  } = {},
): string {
  const prompt = sanitizeBrandMentions(improvedPrompt.trim());
  if (!prompt) return prompt;

  const source = `${options.translatedUserPrompt ?? ""} ${prompt}`;
  const intent = (options.intent ?? "general_edit").trim().toLowerCase();
  if (intent === "color_grading") return prompt;
  if (userRequestedColorChange(options.translatedUserPrompt ?? "")) return prompt;
  if (alreadyPreservesIdentity(prompt)) return prompt;

  const shouldPreserve =
    SCENE_CHANGE_INTENTS.has(intent) ||
    /\b(place|put|move|relocate|background|room|beach|outdoor|indoor|setting|environment|scene)\b/i.test(
      source,
    );

  if (!shouldPreserve) return prompt;

  const colorHint = extractSubjectColorHint(options.imageContext);
  const colorPart = colorHint
    ? ` (same ${colorHint} color)`
    : "";
  const clause =
    `keeping the subject exactly as in the input image${colorPart}: exact original colors, shape, materials, and appearance`;

  if (prompt.endsWith(".")) {
    return `${prompt.slice(0, -1)}, ${clause}.`;
  }
  return `${prompt}, ${clause}.`;
}

function extractSubjectColorHint(imageContext?: string): string | null {
  if (!imageContext) return null;
  const sanitized = sanitizeBrandMentions(imageContext);
  const m = sanitized.match(
    /\b((?:dark|light|bright|deep|vivid|matte|glossy)?\s*(?:blue|red|green|yellow|black|white|pink|purple|orange|brown|gray|grey|teal|navy|turquoise|beige|gold|silver|cyan|magenta)(?:-?\w+)?)\b/i,
  );
  return m?.[1]?.trim().toLowerCase() ?? null;
}

export function buildMinimalEditUserMessage(
  translated: string,
  imageContext?: string,
): string {
  const safeContext = imageContext
    ? sanitizeBrandMentions(imageContext)
    : "Unknown. Still keep the subject's exact original colors and appearance.";
  return `User request: ${translated}

Image context (use subject colors if listed; ignore any brand names):
${safeContext}`;
}

export function buildOptimizerUserMessage(params: {
  translated: string;
  imageContext?: string;
  intent: string;
  contextString: string;
}): string {
  const safeContext = params.imageContext
    ? sanitizeBrandMentions(params.imageContext)
    : "Preserve the existing subject and scene identity.";
  return `
Original editing request:
${params.translated}

Image context (use for subject colors/identity; do not invent a new subject; ignore brand names):
${safeContext}

Detected intent:
${params.intent}

Relevant FLUX documentation:
${params.contextString}
`;
}
