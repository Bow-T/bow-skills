---
name: prompt-design-and-engineering
description: Trigger when writing, refactoring, or debugging an LLM prompt — system prompts, few-shot examples, output formatting, or reducing hallucination and refusals.
---

# Prompt Design & Engineering

A prompt is code that runs on a non-deterministic interpreter. Treat it like code:
version it, test it against fixtures, change one variable at a time, and measure.

## 0. Before you write a token

Answer these. If you can't, the prompt is premature.

- **What is the contract?** Exact input shape, exact output shape, what "correct" means.
- **Who consumes the output?** A human reading text vs. a parser. The parser case is
  stricter and usually wants structured output (tools / JSON schema), not prose.
- **What's the failure cost?** Wrong-but-plausible (hallucination) vs. empty (refusal)
  vs. malformed (parse error). Optimize against the one that hurts.

Red flag: you're already editing wording before you've written a single expected
input/output pair. Stop and write 5 fixtures first.

## 1. Structure the prompt in layers

Keep a fixed skeleton so you change one layer at a time.

1. **Role / objective** — one sentence on what the model is and the single goal.
2. **Context** — the data it reasons over (retrieved docs, user record, prior turns).
3. **Instructions** — numbered, imperative, ordered by priority.
4. **Output contract** — exact format; for parsers, a schema, not a description.
5. **Examples** — few-shot, only the hard/ambiguous cases.

Put long, stable context (docs, schemas) at the **top** and the volatile user query
near the **bottom**. This is also what makes prompt caching effective — a stable prefix
is cacheable; interleaving variable data into the prefix kills the cache.

## 2. Write instructions that constrain, not describe

- Tell it what to **do**, not only what to avoid. "Answer only from CONTEXT; if absent,
  reply `INSUFFICIENT_CONTEXT`" beats "don't make things up."
- One instruction per line, numbered. Conflicting instructions = the model picks one
  silently.
- Name the escape hatch explicitly. A model with no legal way to say "I don't know"
  will hallucinate or refuse — give it a sentinel value.

## 3. Output formatting — make parsing impossible to get wrong

For a TypeScript consumer, prefer the provider's structured-output / tool mechanism over
"return JSON" in prose, then validate at the boundary:

```ts
import { z } from "zod";

const Extraction = z.object({
  sentiment: z.enum(["positive", "neutral", "negative"]),
  topics: z.array(z.string()).max(5),
  confidence: z.number().min(0).max(1),
});

// Never trust raw model text. Parse, then branch on failure.
const parsed = Extraction.safeParse(JSON.parse(modelText));
if (!parsed.success) return retryWithRepairPrompt(modelText, parsed.error);
```

In Dart/Flutter, mirror the contract in the model layer so a bad shape fails loudly at
deserialization, not three screens later:

```dart
factory Extraction.fromJson(Map<String, dynamic> j) => Extraction(
      sentiment: Sentiment.values.byName(j['sentiment'] as String),
      topics: (j['topics'] as List).cast<String>(),
      confidence: (j['confidence'] as num).toDouble(),
    );
```

Red flags: asking for JSON "inside ```json fences" and regexing it out; "respond with
ONLY the JSON" repeated three times (the model already ignored it once).

## 4. Few-shot: examples are tests in disguise

- Add examples only for cases instructions can't pin down (edge formatting, tie-breaks,
  tone). Three sharp examples beat ten generic ones.
- Cover the **boundary**: an empty input, an ambiguous one, one that should hit the
  escape hatch. If every example is a happy path, the model learns only the happy path.
- Keep example outputs byte-identical to your real contract. A trailing comma in an
  example teaches trailing commas.

## 5. Reducing hallucination

- **Ground it.** Inject the source text and forbid outside knowledge. Require citations
  by id: "Every claim must end with `[doc_id]`." Unciteable claims become visible.
- **Separate retrieval from generation.** If a [[octopus-model]]-style data layer or a
  Supabase query feeds the prompt, fetch first, then pass only verified rows — don't ask
  the model to recall facts it was never given.
- **Lower temperature** for extraction/classification (0–0.3). High temperature is for
  ideation, not facts.
- **Ask for uncertainty.** A `confidence` field plus a threshold lets you route low
  confidence to a human or a fallback.

## 6. Reducing refusals & over-caution

- Most spurious refusals come from missing context, not safety. Give the model the
  legitimate reason ("internal admin tool; the user owns this record").
- Replace a hard "you must always X" with a conditional — absolutes trigger refusal when
  an edge case appears.
- If it refuses a benign task, the prompt likely reads as adversarial. Reframe the goal,
  don't add "you are allowed to do this" pleading.

## 7. Debugging loop

When output is wrong, isolate the layer — don't rewrite the whole prompt.

1. **Reproduce** on a single fixed input + temperature 0. Non-determinism hides bugs.
2. **Bisect the layers.** Strip examples → still wrong? It's instructions or contract.
   Strip context → behavior changes? Your context was malformed or too long.
3. **Read what the model actually got.** Log the fully-rendered prompt after template
   interpolation. Most "model is dumb" bugs are an empty variable or a doubled section.
4. **Change one variable, re-run the fixture set.** Record the pass rate.

```ts
// A prompt is a versioned, testable artifact.
const CASES = [
  { in: "ship it 🚀", want: "positive" },
  { in: "", want: "INSUFFICIENT_CONTEXT" },   // boundary
  { in: "it's fine i guess", want: "neutral" }, // ambiguous
];
for (const c of CASES) {
  const got = await classify(c.in);
  if (got !== c.want) console.error(`REGRESS ${JSON.stringify(c.in)}: ${got} != ${c.want}`);
}
```

Red flag: tweaking wording and eyeballing one output. Without the fixture set you are
not engineering, you are gambling.

## 8. Cost & latency hygiene

- Cache the stable prefix; keep variable data out of it (see §1).
- Shorter system prompt > longer one with the same pass rate. Cut instructions that no
  fixture exercises.
- Pick the smallest model that passes the fixtures. Escalate only on measured failures.
- For provider-specific model ids, pricing, caching params, or token limits, consult the
  `claude-api` reference instead of guessing.

## 9. Ship it

- Store the prompt as a versioned file in the repo with its fixture set beside it; a
  prompt change is a code change and gets reviewed like one.
- Commit prompt + fixtures together per the [[commit-pipeline]] skill (Conventional
  Commits + gitmoji).
- Pin the model id. A silent model upgrade is a silent behavior change — re-run fixtures
  before bumping it.

## Checklist

- [ ] Contract (input/output/correctness) written before wording
- [ ] Output is schema-validated at the boundary, not regexed
- [ ] Explicit escape hatch / sentinel for "no answer"
- [ ] Few-shot covers boundary + ambiguous + escape-hatch cases
- [ ] Grounded with citations; temperature matched to task
- [ ] Fixture set exists and passes; model id pinned
