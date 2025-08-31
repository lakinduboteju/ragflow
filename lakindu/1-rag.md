# 1. RAG : Document Parsing and Chunking

Prompt used :-
```
Now, as planned, let's begin the deep dive. I want to trace the journey of a document from raw file to indexed chunks. My focus is on the **parsing** and **chunking** stages.

Based on your explanation, my understanding is that the `deepdoc/` module handles the initial parsing, and its structured output is then fed into the chunking logic within the `rag/` module.

Please help me verify and understand this process by answering the following:

1.  **The Handoff:** Is my understanding of the `deepdoc` -> `rag` data flow correct? Could you trace the high-level code path that orchestrates this? For example, which primary function or class in `api/` receives the uploaded file, calls the `deepdoc` parser, and then passes the result to the `rag` chunker?

2.  **`deepdoc`'s Output:** What is the specific data structure of the output produced by `deepdoc`? I'm very interested in the "schema" of the parsed data before it gets chunked. Is it a list of dictionaries? A Pydantic model? Please provide a simplified Python example of this data structure, showing what metadata is preserved for a piece of text (e.g., page number, content type like 'table' or 'paragraph', coordinates, etc.).

3.  **Default Chunking Logic:** Now, focusing on the `rag/` directory, where is the code for the **default/primary chunking strategy** located?
    * Please point to the specific file(s) and the main function(s)/class(es) responsible.
    * Explain the logic of this default chunker. Does it simply split by a fixed size? Does it use the rich metadata from `deepdoc` to make more intelligent splits (e.g., keeping tables intact, not splitting a title from its paragraph)?

Please use code snippets where they help illustrate the data flow and logic. Let's start here.
```

## Detailed Answer

### 1) The Handoff: deepdoc → rag flow and orchestration

- Flow (standard path)
  - Upload in UI → `document_app.upload` creates `Document` + stores file → user clicks “Run” → `document_app.run` enqueues parse tasks → background worker consumes tasks → calls `rag.app` chunker, which invokes `deepdoc` parsers → chunks embedded and indexed.

Key points in code:

`469:485:/home/laki/git/ragflow/api/apps/document_app.py`
``` python
            if str(req["run"]) == TaskStatus.RUNNING.value:
                doc = doc.to_dict()
                doc["tenant_id"] = tenant_id
                ...
                bucket, name = File2DocumentService.get_storage_address(doc_id=doc["id"])
                queue_tasks(doc, bucket, name, 0)
```

`337:358:/home/laki/git/ragflow/api/db/services/task_service.py`
``` python
    if doc["type"] == FileType.PDF.value:
        file_bin = STORAGE_IMPL.get(bucket, name)
        ...
        for p in range(s, e, page_size):
            task = new_task()
            task["from_page"] = p
            task["to_page"] = min(p + page_size, e)
            parse_task_array.append(task)
```

`401:408:/home/laki/git/ragflow/api/db/services/task_service.py`
``` python
    bulk_insert_into_db(Task, parse_task_array, True)
    DocumentService.begin2parse(doc["id"])
    ...
    assert REDIS_CONN.queue_product(get_svr_queue_name(priority), message=unfinished_task)
```

`241:265:/home/laki/git/ragflow/rag/svr/task_executor.py`
``` python
    chunker = FACTORY[task["parser_id"].lower()]
    ...
    cks = await trio.to_thread.run_sync(lambda: chunker.chunk(
        task["name"], binary=binary, from_page=task["from_page"],
        to_page=task["to_page"], lang=task["language"], callback=progress_callback,
        kb_id=task["kb_id"], parser_config=task["parser_config"], tenant_id=task["tenant_id"]))
```

- Alternative “instant parse for chat upload”
  - `document_app.upload_and_parse` → `doc_upload_and_parse(...)` parses/embeds/indexes immediately via the same `rag.app` chunkers.

`708:746:/home/laki/git/ragflow/api/db/services/document_service.py`
``` python
def doc_upload_and_parse(...):
    ...
    FACTORY = {...}
    ...
    threads.append(exe.submit(FACTORY.get(d["parser_id"], naive).chunk, d["name"], blob, **kwargs))
```

### 2) deepdoc’s output: structure before chunking

- deepdoc returns structured “sections” and “tables”, not Pydantic models. The shape varies slightly by file type but follows this pattern:
  - Sections: list of tuples like `(text, layout_or_position_tag)` or `(text, PIL.Image|None)` depending on parser.
  - Tables: list of items like `((image_or_None, rows_or_html), positions)`.

Examples from code:

`250:251:/home/laki/git/ragflow/rag/app/naive.py`
``` python
        return new_line, tbls
```

`281:297:/home/laki/git/ragflow/rag/app/naive.py`
``` python
        if separate_tables_figures:
            ... return [(b["text"], self._line_tag(b, zoomin)) for b in self.boxes], tbls, figures
        else:
            ... return [(b["text"], self._line_tag(b, zoomin)) for b in self.boxes], tbls
```

These get converted into chunk dicts by `rag/nlp`:

`260:286:/home/laki/git/ragflow/rag/nlp/__init__.py`
``` python
def tokenize_chunks(chunks, doc, eng, pdf_parser=None):
    ...
    d["content_with_weight"] = ck
    d["content_ltks"] = rag_tokenizer.tokenize(t)
    d["content_sm_ltks"] = rag_tokenizer.fine_grained_tokenize(d["content_ltks"])
```

332:345:/home/laki/git/ragflow/rag/nlp/__init__.py
``` python
def add_positions(d, poss):
    ... d["page_num_int"] = [...]
    d["position_int"] = [(pn,left,right,top,bottom)]
    d["top_int"] = [...]
```

302:329:/home/laki/git/ragflow/rag/nlp/__init__.py
``` python
def tokenize_table(tbls, doc, eng, batch_size=10):
    ... builds dicts; attaches image if present; adds positions
```

- Minimal, simplified example (pre- and post-tokenization):

```python
# deepdoc-like parsed output (simplified)
sections = [
  ("Introduction@@0,50,550,120,160", ""),     # text with an inline position tag
  ("Figure 1 caption", ""),                   # another section
]
tables = [
  ((None, "<table>...html...</table>"), [(0, 50, 550, 200, 380)]),  # (img_or_none, html_or_rows), positions
]

# After rag tokenization/chunking (core fields)
chunk = {
  "doc_id": "doc_123", "kb_id": ["kb_1"],
  "docnm_kwd": "Report.pdf",
  "title_tks": ["Report"],

  "content_with_weight": "Introduction ...",
  "content_ltks": [...],
  "content_sm_ltks": [...],

  "page_num_int": [1],
  "position_int": [(1, 50, 550, 120, 160)],
  "top_int": [120],

  "img_id": "",                # set if image saved to MinIO
  "important_kwd": [],         # optional
  "question_kwd": [],          # optional
}
```

For PDFs, the default chunker also tries to crop the source image for each text chunk and attach coordinates:

`275:286:/home/laki/git/ragflow/rag/nlp/__init__.py`
``` python
d["image"], poss = pdf_parser.crop(ck, need_position=True)
add_positions(d, poss)
```

### 3) Default chunking strategy: location and logic

- Location
  - Primary chunker: `rag/app/naive.py`, function `chunk(...)`.
  - Helpers: `rag/nlp/__init__.py` — `naive_merge`, `naive_merge_docx`, `naive_merge_with_images`, `tokenize_chunks`, `tokenize_table`, `add_positions`.

`380:388:/home/laki/git/ragflow/rag/app/naive.py`
``` python
def chunk(filename, binary=None, from_page=0, to_page=100000,
          lang="Chinese", callback=None, **kwargs):
    # Supported file types; uses deepdoc parsers; merges and tokenizes
```

- How it works
  - Uses `parser_config` to choose layout recognition and chunk budget:
    - `chunk_token_num` (default 128–4096 depending on caller)
    - `delimiter` (e.g., `\n!?。；！？`)
    - `layout_recognize`: “DeepDOC”, “Plain Text”, or vision-augmented parsing.
  - For each file type:
    - PDF: deepdoc `Pdf`/`PlainParser`/`VisionParser` extract sections + tables; images/figures optionally enhanced via an image-to-text model; tables are tokenized as intact HTML/text units.
    - DOCX: extracts paragraphs, inline images, and tables; tables become HTML and are kept intact; text paragraphs split by delimiters and merged up to token budget; images combined per section.
    - Excel/CSV: rows are grouped into large chunks; optional `html4excel` produces HTML tables.
    - TXT/Code/Markdown/HTML/JSON: parsed into sections; Markdown images are fetched and merged.
  - Merging and tokenization:
    - `naive_merge` and `naive_merge_with_images` split by configured delimiters and ensure chunk token counts don’t exceed `chunk_token_num`:

`521:563:/home/laki/git/ragflow/rag/nlp/__init__.py`
``` python
def naive_merge(sections, chunk_token_num=128, delimiter="\n。；！？", overlapped_percent=0):
    ...
    # split on delimiters and append until token budget is reached
```

  - Tables: preserved as whole (HTML or batched rows), not split mid-cell:

`302:329:/home/laki/git/ragflow/rag/nlp/__init__.py`
``` python
def tokenize_table(tbls, doc, eng, batch_size=10):
    ... joins rows in batches; keeps images/positions if present
```

  - Positions and images:
    - PDF chunks get `page_num_int`, `position_int`, `top_int` and cropped `image` when available; later saved to MinIO and replaced with `img_id` in the worker.

```282:320:/home/laki/git/ragflow/rag/svr/task_executor.py
    if d.get("image"): save to MinIO → d["img_id"] = f"{kb_id}-{chunk_id}" and remove image
```

- Overall, it’s metadata-aware: it preserves tables, attaches positional metadata and images, and merges text sensibly within token budgets rather than fixed character splits.

---

## Simplified Answer

RAGFlow uses a sophisticated **two-step process**:
1.  **`deepdoc`** acts like a document scanner, breaking the file into raw, structured pieces with detailed metadata (like text, tables, and their exact positions).
2.  **`rag`** then acts like an assembler, intelligently merging these raw pieces into the final, optimized chunks that will be used for search.

Here’s a simpler explanation of each part.

### 1. The Handoff: How `deepdoc` and `rag` Connect

Found that this isn't a simple, single function call. It's handled as a **background job**, which is common in professional applications to avoid making the user wait.

Think of it like ordering food at a busy restaurant: 🍽️

* **You place your order (File Upload):** You upload a file. The code in `api/apps/document_app.py` acts like the **waiter** 🧾, taking your file and creating a record for it in the database.
* **The order goes to the kitchen (Task Queue):** When you click "Run," the system doesn't process the file immediately. Instead, `api/db/services/task_service.py` creates a "task" (an order ticket) and places it in a queue using **Redis** (the ticket system for the chefs).
* **The chef starts cooking (Task Executor):** A background worker, `rag/svr/task_executor.py`, acts like the **chef** 🧑‍🍳. It constantly checks the queue for new tickets. When it picks up your task, it knows which "recipe" (parser/chunker) to use based on the file type and your settings. It then calls the main `chunker.chunk(...)` function, which is the start of the whole process.

So, the "handoff" is actually an API endpoint creating a task, and a separate background worker picking up that task to do the heavy lifting.

### 2. `deepdoc`'s Output: The Raw Materials

This is a key finding. `deepdoc` does **not** just output clean text. It outputs raw, structured data that is much richer.

Imagine breaking a LEGO model into individual bricks, but keeping a note on each brick saying where it came from. That's what `deepdoc` does.

Output is basically a list of tuples (pairs of data).

* **For Text:** It produces something like `("Introduction", "position_metadata")`. The metadata might look like `@@0,50,550,120,160`, which represents the **page number and the exact (x, y) coordinates** of that text block on the page.
* **For Tables:** It produces something like `("<table>...</table>", "position_metadata")`. It intelligently extracts the entire table as HTML and keeps it as **one single unit**, again with its coordinates.

After `deepdoc` creates these raw pieces, a function in `rag/nlp/` assembles them into a more standard Python dictionary for the final chunk. This dictionary contains:
* The actual text (`content_with_weight`).
* The document name and ID.
* The page number (`page_num_int`).
* The precise coordinates (`position_int`).
* An `img_id` if a snapshot of that chunk was taken and saved.

### 3. The Default Chunking Logic: The Assembly Process

This is the most important part. Detailed answer confirmed that RAGFlow uses a **smart, budget-based chunker, not a dumb, fixed-size splitter.** 🧠

* **Location:** The main logic is in `rag/app/naive.py` and its helpers are in `rag/nlp/__init__.py`.
* **How it Works:**
    1.  **It has a token budget:** It's given a maximum token count for each chunk (e.g., 512 tokens).
    2.  **It knows where to split:** It uses natural delimiters like newlines and punctuation (`\n。；！？`) as potential splitting points.
    3.  **It assembles chunks intelligently:** The main function, `naive_merge`, takes the raw pieces from `deepdoc` and starts adding them together one by one. It keeps adding pieces until the next piece would push the chunk over its token budget.
    4.  **It respects document structure:** This is the magic. Because `deepdoc` identified tables as single units, the chunker will **never split a table in half**. It will treat the entire table as one piece to be added to a chunk. The same goes for other elements.

**In summary:** The process is designed for high quality. `deepdoc` deconstructs the document with high fidelity, and the `rag` chunker intelligently reassembles those pieces into meaningful, context-rich chunks that respect the original document's layout.
