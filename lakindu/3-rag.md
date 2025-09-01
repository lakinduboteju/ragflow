# RAG: "Laws" Chunker

Prompt used:-
```
We've established that the default chunking strategy is implemented in `rag/app/naive.py`. I've noticed another chunking implementation related to "laws" (`rag/app/laws.py`) and I want to understand its specific purpose and methodology.

My goal is to compare the "naive" chunker with the "laws" methods. Please help me by answering the following:

1.  **Purpose and Use Case:** What is the primary purpose of the "laws" chunking method? What specific type of document or content is it designed for? Why was a separate method needed instead of just using the "naive" approach?

2.  **Core Differences in Logic:** How does the "laws" chunking algorithm fundamentally differ from the `naive_merge` logic we've already discussed?
    * Does it split text based on different criteria (e.g., legal articles, sections, clauses instead of general delimiters)?
    * Does it process metadata or document structure differently?
    * Please point to the key files and functions that implement the "laws" chunking logic.

3.  **High-Level Explanation:** Could you provide a high-level, conceptual explanation of how the "laws" chunker processes a document? For example, if I upload a legal document, what steps does it take to create chunks?

Please provide code pointers to the relevant implementation so I can study it further.
```

## Detailed Answer

### 1) Purpose and Use Case
- The “laws” chunker targets legal or regulation-style documents (statutes, codes, contracts, manuals with strict numbering/heading hierarchy). It preserves article/section hierarchy and keeps logically complete units intact, which the general “naive” approach (delimiter + token budget) may fragment.
- Why separate: legal texts rely on structured headings (Chapter/Section/Article) and nested bullets; the “laws” method detects these patterns and merges content hierarchically rather than by raw length.

### 2) Core Differences in Logic

- Structural parsing vs. delimiter merging:
  - Laws: detects heading/bullet levels and merges content by hierarchy depth rather than fixed token windows.
  - Naive: splits by delimiters and merges up to a token budget; keeps tables/images intact but does not infer legal hierarchy.

- Key “laws” implementation:
  - Entry (dispatcher) and per-format parsers:
`57:101:rag/app/laws.py`
``` python
def __call__(self, filename, binary=None, from_page=0, to_page=100000):
    ...
    bull = bullets_category([p.text for p in self.doc.paragraphs])
    for p in self.doc.paragraphs:
        ...
        question_level, p_text = docx_question_level(p, bull)
        ...
        lines.append((question_level, p_text))
    ...
    # group paragraphs into hierarchical sections by levels
    ...
    return [s for s in sections if s]
```

`111:141:rag/app/laws.py`
``` python
class Pdf(PdfParser):
    ...
    def __call__(...):
        self.__images__(...)
        self._layouts_rec(zoomin)
        self._naive_vertical_merge()
        return [(b["text"], self._line_tag(b, zoomin)) for b in self.boxes], None
```

  - Chunk orchestration (core flow):
`143:212:rag/app/laws.py`
``` python
def chunk(...):
    ...
    # parse docx/pdf/txt/html/doc into sections
    ...
    remove_contents_table(sections, eng)
    make_colon_as_title(sections)
    bull = bullets_category(sections)
    chunks = hierarchical_merge(bull, sections, 5)
    return tokenize_chunks(["\n".join(ck) for ck in chunks], doc, eng, pdf_parser)
```

- Supporting NLP utilities (legal-aware signals):
  - Bullet pattern category detection (e.g., “第x章/节/条”, Roman numerals, English headings):
`208:226:rag/nlp/__init__.py`
``` python
def bullets_category(sections):
    ...
    return res
```
  - Title/heading extraction heuristics:
`379:399:rag/nlp/__init__.py`
``` python
def make_colon_as_title(sections): ...
```
  - Hierarchical merge by detected levels:
`431:518:rag/nlp/__init__.py`
``` python
def hierarchical_merge(bull, sections, depth):
    ...
    return res
```
  - DOCX heading-level scorer:
`617:627:rag/nlp/__init__.py`
``` python
def docx_question_level(p, bull=-1):
    ...
    return int(level), txt
```
  - Final tokenization:
`267:286:rag/nlp/__init__.py`
``` python
def tokenize_chunks(chunks, doc, eng, pdf_parser=None): ...
```

- Contrast with “naive”:
  - Naive parser (multi-format, tables/images-aware) then delimiter-based merging:
`380:399:rag/app/naive.py`
``` python
def chunk(...):
    ...
    doc = {"docnm_kwd": filename, "title_tks": ...}
```
`440:482:rag/app/naive.py`
``` python
# PDF with DeepDOC / Plain / Vision; tables/figures extracted; tokenize_table
```
`565:575:rag/nlp/__init__.py`
``` python
def naive_merge(sections, chunk_token_num=128, delimiter=...): ...
```
  - Naive prioritizes token budget; Laws prioritizes legal structure (chapters/sections/articles).

### 3) High-Level “Laws” Chunker Flow

- DOCX:
  1. Read paragraphs; detect overall bullet style with `bullets_category`.
  2. For each paragraph, assign a heading/level via `docx_question_level` (heading style or bullet regex).
  3. Build hierarchical sections (group a title with its child paragraphs) via `hierarchical_merge(..., depth=5)`.
  4. Pre-clean: remove contents tables (`remove_contents_table`), split titles ending with colon (`make_colon_as_title`).
  5. Emit chunks by joining each section’s lines; tokenize with `tokenize_chunks`.

- PDF:
  1. OCR and layout analysis; vertical merge lines (`_naive_vertical_merge`) to produce ordered text + position tags.
  2. Append inline position tags to text; then the same legal pre-processing (contents removal, colon-title).
  3. Detect bullet style; `hierarchical_merge` into structured chunks; `tokenize_chunks` to finalize.

- TXT/HTML/DOC:
  - Extract sections; remove contents; colon-title; bullet detection; hierarchical merge; tokenize.

Result: chunks reflect legal document hierarchy (e.g., Chapter → Section → Article) rather than arbitrary delimiter windows, improving retrieval and semantic coherence for legal queries.

---

## Simplified Answer

### The Big Picture: Specialist vs. Generalist 🏛️

The simplest way to think about it is:
* The **`naive`** chunker is a **generalist**. It's designed to work reasonably well on *any* kind of document (articles, reports, web pages). Its main goal is to create chunks of a specific *size* without breaking sentences too awkwardly.
* The **`laws`** chunker is a **specialist**. It's expertly do one specific job: understanding the strict, hierarchical structure of **legal and formal documents** (like laws, contracts, and regulations). Its main goal is to preserve the document's logical *structure*.

### 1. Purpose: Why Does the "Laws" Chunker Exist?

Legal documents have a meaningful structure that is critical to their interpretation. A single legal article might be short, but it needs to be understood in the context of the Section and Chapter it belongs to.

The `naive` chunker, which just splits text by periods and fills up a token budget, might do this:
* **Problem:** It could split a single, coherent legal article in half. Or, it could group Article 1 with the title of Article 2, creating a confusing and contextually incorrect chunk.

The `laws` chunker was created to solve this. It ensures that a chunk always contains a **logically complete unit**, like an entire article or a section with all its sub-points.

### 2. Core Differences in Logic: Size vs. Structure

This is where above code analysis is key. The two methods think about documents in fundamentally different ways.

* **The `naive` method thinks about SIZE 🧱:**
    * Its main tool is `naive_merge`.
    * Its logic is: "Start a new chunk. Keep adding sentences until I'm close to my 512-token budget. Then, stop and start the next chunk." It's simple and effective for general text.

* **The `laws` method thinks about STRUCTURE 🧠:**
    * Its main tool is `hierarchical_merge`.
    * Its logic is a multi-step process:
        1.  **Scan for Patterns:** It first runs a function called `bullets_category`. This is a smart scanner that recognizes heading styles like "Chapter 1", "Section A", "Article (i)", or "第x条" (for Chinese law).
        2.  **Assign Levels:** For each paragraph, it determines its level in the hierarchy. "Chapter 1" might be Level 1, "Section 1.1" is Level 2, and "Article 1.1.a" is Level 3.
        3.  **Group by Hierarchy:** The `hierarchical_merge` function then acts like an assembler. It groups a heading with all of its content and sub-headings until it hits the next heading of the *same or higher level*.

**Simple Analogy:** Imagine organizing a book.
* `naive` would be like tearing out pages in stacks of 10.
* `laws` would be like carefully separating the book into its original Chapters and Sections. The resulting "chunks" are the actual chapters, which are much more meaningful.

### 3. High-Level Flow of the "Laws" Chunker

Here is the step-by-step process:

1.  **Parse the Document:** First, the system extracts all the raw text from the file (PDF, DOCX, etc.), just like the naive method.
2.  **Clean Up:** It does some pre-processing, like finding and removing the table of contents.
3.  **Identify the Structure:** It runs `bullets_category` to figure out the heading and numbering style used in the document.
4.  **Create the Hierarchy:** It goes through the document line by line, assigning a "level" to each piece of text based on the structure it identified.
5.  **Merge Logically:** It uses `hierarchical_merge` to group the text. For example, it will create one chunk for "Article 1" and all its text, another chunk for "Article 2" and its text, and so on.
6.  **Finalize:** The final, structurally-aware text blocks are then tokenized and prepared for embedding.

The end result is a set of chunks that perfectly mirror the logical sections of the original legal document, making them far more accurate and useful for answering legal questions. 📜
