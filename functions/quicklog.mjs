/* Quick log: turns "emails 2:30 to 3, then calls for an hour and a half" into
   structured time entries. The app shows them for confirmation before saving,
   and saves them through its normal signed-in path - this function never
   touches the database.

   Locked down:
     - the caller must be signed in (their Supabase token is verified), and
     - their email must be listed in QUICKLOG_ALLOWED_EMAILS, so nobody else
       who signs up can spend the API key.
   Environment variables (set in Netlify, never in code):
     ANTHROPIC_API_KEY, QUICKLOG_ALLOWED_EMAILS (comma separated) */

const MODEL = "claude-haiku-4-5-20251001";
const SUPA_URL = process.env.SUPABASE_URL || "https://vybypyeyzfgakenkotbw.supabase.co";
/* The publishable key is public by design (it is also in index.html). */
const SUPA_KEY = process.env.SUPABASE_ANON_KEY || "sb_publishable_-aDVEq7DzlUz7hlvpgkUhw_i6yXO2SU";

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

async function verifiedEmail(req) {
  const auth = req.headers.get("authorization") || "";
  if (!/^Bearer .+/.test(auth)) return null;
  try {
    const r = await fetch(SUPA_URL + "/auth/v1/user", { headers: { apikey: SUPA_KEY, authorization: auth } });
    if (!r.ok) return null;
    const u = await r.json();
    return u && u.email ? String(u.email).toLowerCase() : null;
  } catch (e) { return null; }
}

const TOOL = {
  name: "log_entries",
  description: "Report the time entries described by the user, or a question if they cannot be worked out.",
  input_schema: {
    type: "object",
    properties: {
      entries: {
        type: "array",
        items: {
          type: "object",
          properties: {
            date: { type: "string", description: "YYYY-MM-DD, local date the entry happened on" },
            start: { type: "string", description: "HH:MM, 24-hour, local time" },
            end: { type: "string", description: "HH:MM, 24-hour, local time. Empty string when ongoing is true." },
            ongoing: { type: "boolean", description: "True if the person is doing this right now or is starting it now and it has no end yet (e.g. 'about to go into a meeting'). Then start is the time it begins (now unless they say otherwise) and end is an empty string." },
            channel_id: { type: ["string", "null"], description: "Exact id from the channel list, or null if no confident match" },
            channel_guess: { type: "string", description: "What the user called it" },
            note: { type: ["string", "null"], description: "Short detail such as a person or topic, max 60 characters, or null" }
          },
          required: ["date", "start", "end", "ongoing", "channel_id", "channel_guess", "note"]
        }
      },
      question: { type: ["string", "null"], description: "One short question if the times cannot be determined, else null" }
    },
    required: ["entries", "question"]
  }
};

export default async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const email = await verifiedEmail(req);
  if (!email) return json({ error: "not_signed_in" }, 401);
  const allowed = String(process.env.QUICKLOG_ALLOWED_EMAILS || "").toLowerCase().split(",").map((s) => s.trim()).filter(Boolean);
  if (!allowed.length) return json({ error: "not_configured" }, 503);
  if (allowed.indexOf(email) < 0) return json({ error: "not_allowed" }, 403);
  if (!process.env.ANTHROPIC_API_KEY) return json({ error: "no_api_key" }, 503);

  let body;
  try { body = await req.json(); } catch (e) { return json({ error: "bad_request" }, 400); }
  const text = String(body.text || "").slice(0, 2000).trim();
  if (!text) return json({ error: "empty" }, 400);
  const channels = (Array.isArray(body.channels) ? body.channels : []).slice(0, 300)
    .map((c) => ({ id: String(c.id), label: String(c.label || ""), parent: c.parent ? String(c.parent) : null }));
  const existing = (Array.isArray(body.existing) ? body.existing : []).slice(0, 200)
    .map((x) => ({ date: String(x.date), start: String(x.start), end: String(x.end), label: String(x.label || "") }));

  const system = [
    "You turn a person's plain-English description of how they spent their time into timeline entries for a time tracker.",
    "Today is " + String(body.today) + ", and it is now " + String(body.nowLocal) + " (" + String(body.tz || "local time") + "). Resolve 'yesterday', 'this morning', etc. from that.",
    "Chain sequences: 'then' means the next entry starts when the previous one ended. 'Finished X at 2:30' means X ended at 2:30, so the next thing starts at 2:30.",
    "Durations ('30 minutes', 'an hour and a half') set the end from the start. Output 24-hour HH:MM.",
    "If AM/PM is not stated, assume a normal working day (about 6 AM to 9 PM).",
    "Use the existing entries to anchor: if the person says they finished at 2:30, the entry they refer to may already be listed. Do not re-create existing entries; output only new ones.",
    "Match each activity to a channel by its id from the list. Subcategories have a parent; prefer the most specific match. If no channel clearly matches, use null for channel_id and put what they said in channel_guess. Never invent ids.",
    "Entries must not overlap each other or the existing entries, and must not end in the future. If you cannot work out the times, return no entries and ask one short question.",
    "If the person says they are starting something now, are about to do it, or are still doing it ('about to walk into a meeting for an hour', 'on a call now'), return that entry with ongoing=true, start=now (or the time they say) and end=''. At most one entry may be ongoing, and it must be the last in time. Do not invent an end from a stated duration for an ongoing entry.",
    body.window && body.window.start ? "This is a periodic check-in. The person is reporting on the stretch from " + String(body.window.start) + " to " + String(body.window.end) + " on " + String(body.window.date) + ". Unless they say otherwise, what they describe happened in that stretch: if they describe one activity, it covers all of it; if several, split it in the order told, dividing the stretch sensibly when no times are given." : "",
    "Channels: " + JSON.stringify(channels),
    "Existing entries: " + JSON.stringify(existing)
  ].filter(Boolean).join("\n");

  let resp;
  try {
    resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": process.env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({
        model: MODEL, max_tokens: 1500, system,
        tools: [TOOL], tool_choice: { type: "tool", name: "log_entries" },
        messages: [{ role: "user", content: text }]
      })
    });
  } catch (e) { return json({ error: "upstream" }, 502); }
  if (!resp.ok) return json({ error: "upstream", status: resp.status }, 502);
  const data = await resp.json();
  const use = (data.content || []).find((b) => b.type === "tool_use");
  if (!use || !use.input) return json({ error: "no_result" }, 502);
  const entries = (Array.isArray(use.input.entries) ? use.input.entries : []).map((e) => ({
    date: String(e.date || ""), start: String(e.start || ""), end: String(e.end || ""), ongoing: !!e.ongoing,
    channel_id: e.channel_id ? String(e.channel_id) : null,
    channel_guess: String(e.channel_guess || ""),
    note: e.note ? String(e.note).slice(0, 60) : null
  }));
  return json({ entries, question: use.input.question || null });
};
