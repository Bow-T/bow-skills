---
name: rag-system-engineering
description: Use when building or debugging retrieval-augmented generation — designing chunking/embedding, choosing a vector store and retrieval method, tuning hybrid/reranked search, grounding LLM answers in sources, or fixing hallucinated/irrelevant RAG results.
---

# RAG System Engineering

A senior engineer's process for shipping retrieval that returns grounded, accurate answers. RAG fails at retrieval far more often than at generation — spend your effort there.

## 0. Decide whether you even need RAG

- Corpus fits in the context window and rarely changes → just stuff it in the prompt with caching. Skip RAG.
- Answers need fresh/private/large knowledge → RAG.
- Answers need reasoning over a few known docs → pass those docs directly, no retrieval.

Do not build a vector DB to answer questions about 30 pages.

## 1. Build an eval set BEFORE writing retrieval code

Without this you are tuning blind. Collect 30-50 real questions, each with the source chunk(s) that should answer it.

Track two numbers from day one:
- **Retrieval recall@k** — fraction of questions where a correct chunk is in the top-k.
- **Answer groundedness** — fraction of answers fully supported by retrieved text (no invention).

Red flag: you are adjusting chunk size by vibes. Every change must move a number.

## 2. Ingestion and chunking

Chunk on **semantic boundaries**, not fixed character counts. Splitting mid-sentence destroys embedding quality.

- Structured docs (Markdown, HTML): split by heading hierarchy; keep the heading path as a prefix in each chunk.
- Prose: ~300-800 tokens per chunk with ~10-15% overlap.
- Code/tables: never split a function or a table row group across chunks.

Always store metadata alongside every chunk: `source_id`, `title`, `section`, `url`, `updated_at`. You will need it for filtering, citation, and freshness.

```sql
-- Supabase + pgvector schema
create extension if not exists vector;

create table doc_chunks (
  id          uuid primary key default gen_random_uuid(),
  source_id   text not null,
  title       text,
  section     text,
  content     text not null,
  embedding   vector(1024),          -- match your embedding model's dimension
  fts         tsvector generated always as (to_tsvector('english', content)) stored,
  updated_at  timestamptz not null default now()
);

create index on doc_chunks using hnsw (embedding vector_cosine_ops);
create index on doc_chunks using gin (fts);
```

Red flag: re-embedding the whole corpus on every deploy. Hash chunk content and only re-embed changed chunks.

## 3. Embeddings

- Pick the model first; it fixes your vector dimension and your schema.
- Use the **same** model for indexing and for queries. A mismatch silently returns garbage.
- Normalize vectors if your store uses dot-product so cosine and dot agree.
- Some models want an instruction prefix on queries vs. documents — read the model card, do not guess.
- Version your embedding model in config. Changing it means a full re-index, not a hot swap.

In Flutter/Dart clients, never embed on-device or ship the embedding key. Call a Supabase Edge Function (TypeScript) that owns the key and writes vectors server-side.

## 4. Retrieval: start hybrid, not pure vector

Pure semantic search misses exact terms (error codes, names, SKUs). Pure keyword misses paraphrase. Combine both and fuse the ranks.

Use **Reciprocal Rank Fusion** — it needs no score calibration between the two systems.

```typescript
// Edge Function: fuse vector + full-text results by rank
function rrf(vectorIds: string[], ftsIds: string[], k = 60): string[] {
  const score = new Map<string, number>();
  const add = (ids: string[]) =>
    ids.forEach((id, i) => score.set(id, (score.get(id) ?? 0) + 1 / (k + i + 1)));
  add(vectorIds);
  add(ftsIds);
  return [...score.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id);
}
```

Retrieve ~20-40 candidates per branch, fuse, then trim. Apply metadata filters (tenant, recency, doc type) in the SQL query, not after fetching.

## 5. Rerank before you hand text to the LLM

Bi-encoder retrieval is fast but coarse. A cross-encoder reranker reads (query, chunk) together and reorders the fused candidates by true relevance. This is usually the single biggest precision win.

- Rerank the top ~30 candidates down to the top ~5-8 you actually pass to the model.
- Drop chunks below a relevance threshold entirely. Fewer, better chunks beat more noise.

Red flag: passing 20 chunks "to be safe." Irrelevant context actively degrades the answer and invites hallucination.

## 6. Grounded generation

Construct the prompt so the model can only answer from sources, and must cite them.

- Number each chunk; instruct the model to cite by number.
- Instruct it to say "I don't know" when the context lacks the answer — and reward that in your evals.
- Put the question after the context so it is not buried in a long prefix.
- For Claude, prefer the native citations feature over hand-rolled `[1]` parsing when document fidelity matters — it returns exact cited spans you can verify. See the **claude-api** skill for the request shape and current model IDs; do not hardcode model strings from memory.

```
Answer ONLY using the numbered sources below. Cite each claim as [n].
If the sources do not contain the answer, say "I don't know."

[1] {title} — {content}
[2] ...

Question: {user_question}
```

## 7. Verify groundedness

Do not trust the model to police itself silently. Either:
- Use citation spans and check each cited span actually exists in the retrieved chunk, or
- Run a cheap second-pass check: "Is every claim supported by the sources? List unsupported claims."

Surface citations in the UI so users can audit. A wrong-but-cited answer is caught; a wrong-and-confident one is not.

## 8. Debugging a bad answer — isolate the stage

Always answer this first: **was the right chunk retrieved?**

1. Hallucinated or vague → check whether the correct chunk was in the retrieved set.
   - Not retrieved → retrieval problem (go to step 2).
   - Retrieved but ignored → generation problem (go to step 4).
2. Correct chunk missing from candidates → chunking too coarse/fine, embedding mismatch (query vs. doc model), or a metadata filter excluded it. Inspect the raw top-k.
3. Correct chunk retrieved but ranked low → add/tune reranking; check hybrid fusion weights; verify keyword branch is firing for exact-term queries.
4. Right context, wrong answer → prompt isn't constraining to sources, context window truncated mid-chunk, too many distractor chunks, or contradictory chunks. Reduce k, raise the rerank threshold.
5. Stale answer → `updated_at` filtering missing, or changed docs were never re-embedded.

Log retrieved chunk IDs + scores with every answer. You cannot debug retrieval you cannot see.

## Red flags checklist

- No eval set → you are guessing.
- Different embedding model for query and index → silent garbage.
- Fixed-size chunks cutting mid-sentence → poor recall.
- Pure vector search only → misses exact terms.
- No reranking → low precision, more hallucination.
- Passing 15+ chunks → noise drowns the answer.
- No citations / no groundedness check → wrong answers ship undetected.
- Re-embedding everything per deploy → slow, expensive, unnecessary.

## Commit & cross-references

When committing RAG changes, follow the **commit-pipeline** skill (Conventional Commits + gitmoji). For the LLM generation call, model selection, and citation API, consult the **claude-api** skill rather than recalling model IDs.
