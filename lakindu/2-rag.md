# 1. RAG : Retrieval

Prompt used :-
```
I understand how a document is processed into high-quality chunks, let's focus on the next crucial step: **retrieval**. My goal is to understand how RAGFlow takes a user's query and finds the most relevant chunks from the indexed knowledge base.

Based on the documentation, RAGFlow uses a hybrid search approach. Let's dive into how that's implemented.

Please answer the following questions:

1.  **High-Level Retrieval Flow:** Could you trace the main code path for a standard retrieval operation? Which API endpoint (likely in `api/apps/`) receives the user's question, and which key services or functions in the `rag/` directory are called to orchestrate the search?

2.  **Hybrid Search Implementation:** The core of the retrieval is **hybrid search**.
    * Where in the `rag/` directory is this logic located? Please point me to the specific files and functions that are responsible for querying both the keyword index (e.g., Elasticsearch BM25) and the vector index.
    * How are the scores from these two different search methods **combined** or **fused**? Does it use a simple weighted sum, or a more advanced technique like Reciprocal Rank Fusion (RRF)? The code that handles this score fusion is what I'm most interested in.

3.  **Query Pre-processing:** Before the search, what happens to the user's query string itself? Is it transformed, expanded, or embedded? Please show me where this query pre-processing logic lives.

4.  **Knowledge Graph Retrieval:** For the more advanced case involving knowledge graphs (using the `graphrag/` directory), how does the retrieval process differ from the standard approach? Briefly, how does it extract entities from a query and use them to find relevant information in the graph?

Please walk me through these points with relevant code pointers to help me connect the concepts to the implementation.
```

## Code Oriented Answer

### 1) High-Level Retrieval Flow

- Entry points:
  - Dialog/QA and chunk listing use:

`346:371:/home/laki/git/ragflow/api/apps/chunk_app.py`
``` python
ranks = settings.retrievaler.retrieval(question, embd_mdl, tenant_ids, kb_ids, page, size, ...)
if use_kg: ck = settings.kg_retrievaler.retrieval(...)
```

  - Generic API:

`854:887:/home/laki/git/ragflow/api/apps/api_app.py`
``` python
def retrieval(): ... ranks = settings.retrievaler.retrieval(...)
```

- Retrievaler wiring:

`177:194:/home/laki/git/ragflow/api/settings.py`
``` python
docStoreConn = ... (ES/OpenSearch/Infinity)
retrievaler = search.Dealer(docStoreConn)
kg_retrievaler = kg_search.KGSearch(docStoreConn)
```

- Core implementation:

`347:439:/home/laki/git/ragflow/rag/nlp/search.py`
``` python
class Dealer:
  def retrieval(self, question, embd_mdl, tenant_ids, kb_ids, page, page_size, ...)
    sres = self.search(...)
    sim, tsim, vsim = self.rerank(...) or self.rerank_by_model(...)
    ... build response with per-chunk scores and highlights
```

### 2) Hybrid Search Implementation

- Where the hybrid happens:
  - Text match + Vector match combined in one search via DocStore expressions:

`110:121:/home/laki/git/ragflow/rag/nlp/search.py`
``` python
matchDense = self.get_vector(qst, embd_mdl, topk, req.get("similarity", 0.1))
fusionExpr = FusionExpr("weighted_sum", topk, {"weights": "0.05,0.95"})
matchExprs = [matchText, matchDense, fusionExpr]
res = self.dataStore.search(..., matchExprs, ...)
```

- Score fusion inside service:
  - After initial retrieval, scores are re-ranked with token+vector hybrid similarity, plus optional rank-feature and reranker:

`279:316:/home/laki/git/ragflow/rag/nlp/search.py`
``` python
def rerank(self, sres, query, tkweight=0.3, vtweight=0.7, ...):
  keywords = self.qryr.question(query)[1]
  ins_embd = vectors from each chunk (field q_{dim}_vec)
  ins_tw = tokens from content/title/important/question (weighted)
  rank_fea = self._rank_feature_scores(...)
  sim, tksim, vtsim = self.qryr.hybrid_similarity(...)
  return sim + rank_fea, tksim, vtsim
```

- Fusion method:
  - Search-time fusion through `FusionExpr("weighted_sum", {"weights": "0.05,0.95"})`.
  - Post-search reranking uses a weighted sum of token vs vector similarity:

`219:227:/home/laki/git/ragflow/rag/nlp/query.py`
``` python
return np.array(sims[0]) * vtweight + np.array(tksim) * tkweight
```

- No RRF in code paths above; it uses weighted-sum fusion both in the datastore fusion and in the reranker. Rank-feature (tags + pagerank) adds a small bias:

`252:277:/home/laki/git/ragflow/rag/nlp/search.py`
``` python
return np.array(rank_fea)*10. + pageranks
```

- DocStore APIs supporting hybrid:

`123:131:/home/laki/git/ragflow/rag/utils/doc_store_conn.py`
``` python
class FusionExpr(method='weighted_sum', topn, fusion_params)
```

### 3) Query Pre-processing

- Full-text query building and expansion:

`26:39:/home/laki/git/ragflow/rag/nlp/query.py`
``` python
class FulltextQueryer:
  query_fields = ["title_tks^10", "title_sm_tks^5", "important_kwd^30", ...]
```

`85:99:/home/laki/git/ragflow/rag/nlp/query.py`
``` python
def question(self, txt, min_match=0.6):
  txt = add_space_between_eng_zh(...)
  normalize: lower, Q2B, trad2simp, strip, rmWWW
  if English: tokenize, term weights, synonyms, bi-grams, boost, quote phrases
  else: term weighting, fine-grained tokenize, synonyms, phrase queries
  return MatchTextExpr(query_fields, query, minimum_should_match=...)
```

- Token similarity and hybrid scorer live here too:

`219:227:/home/laki/git/ragflow/rag/nlp/query.py`
``` python
def hybrid_similarity(...): cosine + token_similarity weighted
```

- Embedding for vector search:

`48:56:/home/laki/git/ragflow/rag/nlp/search.py`
``` python
def get_vector(...): emb_mdl.encode_queries(txt) → MatchDenseExpr on q_{dim}_vec
```

### 4) Knowledge Graph Retrieval

- Different flow under `graphrag`:

`33:66:/home/laki/git/ragflow/graphrag/search.py`
``` python
class KGSearch(Dealer):
  def query_rewrite(...): LLM extracts entity types and entities from query
```

- Entity and relation retrieval over graph-indexed docs:

`106:139:/home/laki/git/ragflow/graphrag/search.py`
``` python
get_relevant_ents_by_keywords(...)  # knowledge_graph_kwd='entity' + dense match
get_relevant_relations_by_txt(...)  # knowledge_graph_kwd='relation'
get_relevant_ents_by_types(...)     # entity_type_kwd filter, ordered by pagerank
```

- Fusion and scoring differ: sim × pagerank, plus n-hop paths:

`192:226:/home/laki/git/ragflow/graphrag/search.py`
``` python
score entities/relations by sim * pagerank; adjust by n-hop paths and type matches
```

- Output is a synthesized “graph context” chunk, optionally with community reports:

`274:289:/home/laki/git/ragflow/graphrag/search.py`
``` python
return { chunk_id, content_with_weight: entities + relations + community_report, ... }
```

That covers endpoint → retrievaler wiring, hybrid search and fusion, query preprocessing, and KG retrieval differences.

---

## Simplified Answer

In essence, Code oriented answer has confirmed that RAGFlow uses a highly sophisticated, multi-stage process for retrieval. It's not just a simple search; it's more like a detective meticulously gathering and weighing evidence.

### 1. The High-Level Flow: Who Handles the Search?

This section answers the question: "When a user asks a question, where does the request go?"

* **The Front Door:** The user's query first hits an API endpoint, specifically in files like `chunk_app.py` or `api_app.py`. This is the entry point.
* **The Search Manager:** The API doesn't do the search itself. It delegates the job to a central "manager" object called the **`retrievaler`**. This object is created once when the application starts (in `api/settings.py`) and is responsible for all search-related tasks.
* **The Real Worker:** The `retrievaler` is an instance of the `Dealer` class found in `rag/nlp/search.py`. Think of this **`Dealer`** as the main contractor for the search job. Its primary method, `retrieval(...)`, orchestrates the entire process of searching and reranking.

**Simple Analogy:** The API is the receptionist who takes your request. They pass it to the project manager (`retrievaler`), who then tasks the expert engineer (`Dealer` class) to do the actual work.

### 2. Hybrid Search: The Two-Stage Search Strategy ⚖️

This is the core of the retrieval logic. We found that RAGFlow uses a **two-stage hybrid search**, which is very effective.

* **Stage 1: Initial Search at the Database Level.**
    When RAGFlow first queries the database (like Elasticsearch), it doesn't just do a vector search. It uses a `FusionExpr("weighted_sum", {"weights": "0.05,0.95"})`.
    * **What this means:** It tells the database to combine a traditional keyword search (worth 5%) and a vector similarity search (worth 95%) in a single operation. This quickly finds a list of generally relevant candidates, with a strong emphasis on semantic meaning from vectors.

* **Stage 2: Refined Reranking in the Application.**
    After getting the initial results back, RAGFlow does a *second*, more careful evaluation in the `rerank` function.
    * **What this means:** It re-calculates a new hybrid score for each retrieved chunk. This time, the weights are more balanced (`tkweight=0.3, vtweight=0.7`), combining token (keyword) similarity and vector similarity. It might also add bonus points for other factors, like whether the chunk has important tags.

**Simple Analogy:** It's like finding a book in a library.
* **Stage 1:** You quickly run to the "Computer Science" section (the initial, vector-heavy search).
* **Stage 2:** You then carefully read the titles and summaries of the books on that shelf to pick the absolute best one (the refined reranking).

### 3. Query Pre-processing: Making the Search Smarter 🕵️‍♂️

This section explains that RAGFlow doesn't just use the user's raw question. It enhances it first to get better results.

* **Enriching the Query:** The code in `rag/nlp/query.py` acts like a detective. It takes the user's query and:
    * **Cleans it up:** Normalizes text (lowercase, etc.).
    * **Finds Clues:** It identifies synonyms and related phrases (bi-grams) to broaden the search.
    * **Prioritizes Evidence:** It creates a more complex query that gives massive boosts to matches found in important fields. For example, `important_kwd^30` means a match in the "important keywords" field is **30 times more valuable** than a match in the normal content.
* **Creating the Vector:** For the vector search part, it simply takes the processed query text and passes it to the embedding model to turn it into a vector (a list of numbers).

### 4. Knowledge Graph Retrieval: A Completely Different Path 🕸️

Code oriented answer confirms that when you're using a Knowledge Graph (KG), the process is fundamentally different. It's less about finding text and more about exploring relationships.

* **Step 1: Understand the Query's Intent:** It uses an LLM to analyze the user's question and extract key "entities" and "types." For a query like "Who is the CEO of Google?", it pulls out `Entity: Google` and `Relationship: CEO`.
* **Step 2: Search the Graph, Not Text:** It then searches the knowledge base for these specific entities and relations. It also uses "PageRank" (a score of how important a node is in the graph) to prioritize results.
* **Step 3: Build a New Answer:** Instead of returning a raw text chunk, it synthesizes a new "graph context" chunk from the facts it found (e.g., "Sundar Pichai is related to Google via the 'CEO' relationship.").

This approach is much more structured and is designed for answering factual questions where relationships between entities are key.
