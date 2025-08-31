# RAGFlow

## 0. Code Overview

Prompt used :-
```
Here I have the entire `ragflow` repository cloned and open in my editor.

**Your Role:** You are an expert senior software engineer and the original architect of the RAGFlow project. Your task is to onboard me, a new developer, to the codebase.

**Our Goal:** I want to understand the entire project, starting from a high-level overview and gradually diving into the implementation details. We will do this in a structured, step-by-step manner.

Please begin with **Part 1** and **Part 2**.

---

**Part 1: High-Level Architecture**

Please provide a concise overview of RAGFlow's architecture. I'm looking for a conceptual understanding. Please explain:
1.  **The main logical components** of the system (e.g., Frontend UI, Backend API, Document Processing Service, Retrieval Engine, Database Layer, etc.).
2.  **How these components interact.** A simple text-based data flow would be excellent (e.g., "User uploads a PDF via the Frontend -> Backend API receives the file -> Document Processing Service parses and chunks it -> Chunks are embedded and stored in the Vector DB...").
3.  **The key technologies and frameworks** used for each major component (e.g., Python/FastAPI for the backend, React/Next.js for the frontend, specific database technologies used, etc.).

---

**Part 2: Codebase Organization (Directory & Module Structure)**

Next, please walk me through the organization of the source code at the top level of this repository. For each major directory, provide its name and a brief, one-sentence description of its purpose.

Please use the following format:
* `api/`: [Purpose of this directory]
* `deepdoc/`: [Purpose of this directory]
* `docker/`: [Purpose of this directory]
* `frontend/`: [Purpose of this directory]
* *...and so on for all other key directories.*

After listing them, please highlight the **top 3 most important directories** that I should focus on first to understand the core logic of the application.

---

After I review your response to these two parts, I will ask you to begin the deep dive. My next prompt will likely be something like, "Let's deep dive into the `deepdoc/` directory. What are the key modules here and how do they implement the document understanding logic?"

Let's begin.
```

### Part 1: High-Level Architecture

- **Main logical components**
  - **Frontend UI (`web/`)**: React 18 app built with UmiJS, Ant Design, Tailwind; talks to REST APIs and streaming endpoints.
  - **Backend API (`api/`)**: Flask-based HTTP server (Werkzeug), CORS, Flasgger/Swagger docs; orchestrates ingestion, search, chat, and admin; exposes SDK-style routes under versioned prefixes.
  - **Document Processing & Chunking (`deepdoc/`, `rag/`)**:
    - `deepdoc/`: Parsers (PDF/Office/image), layout/vision helpers.
    - `rag/`: RAG pipeline: chunking, embedding, indexing, retrieval, reranking, and answer generation; task execution logic in `rag/svr/`.
  - **Retrieval/Index Engine (external services)**: Pluggable “document engine”
    - Default: **Elasticsearch** (or **OpenSearch**) for text+vector indexes.
    - Alternative: **Infinity** (columnar/vector DB) via Thrift/HTTP.
  - **Database Layer**:
    - **MySQL** (or Postgres) via Peewee ORM for metadata (users, KBs, docs, tasks, dialogs).
    - **Redis** for locks and lightweight coordination.
  - **Object Storage**: **MinIO** S3-compatible for raw files and generated assets (e.g., thumbnails).
  - **Agent & Tools (`agent/`, `agentic_reasoning/`, `agent/tools/`)**: Agent workflows, tool-calling, and prebuilt templates.
  - **Sandbox Executor (`sandbox/`)**: Sidecar FastAPI service to safely run user code/tools in isolated containers.
  - **Gateway/Proxy**: Nginx in container for reverse proxying frontend/backend.

- **How components interact (typical flows)**
  - **Ingestion**
    1. User uploads file in Frontend → Backend receives stream (Flask) → persists to MinIO.
    2. Backend creates DB records (`Document`, `Task`) → triggers processing.
    3. `deepdoc/` parsers extract structure/content → `rag/` chunkers split text → `rag/llm` embeddings encode chunks.
    4. Chunks + vectors are indexed into Elasticsearch/OpenSearch (or Infinity).
    5. Progress updates via DB/Redis; UI polls or receives updates; document status becomes ready.
  - **Search/Q&A**
    1. User asks a question in Frontend → Backend normalizes query.
    2. Retriever pulls top candidates from document engine using vector similarity + keyword filters.
    3. Optional rerank (default: BAAI bge reranker) → top-K chunks chosen.
    4. LLM is prompted with retrieved context → streaming answer returned to Frontend.
    5. References (citations) and highlights are attached based on chunk IDs.
  - **Agent workflow**
    1. Agent templates (JSON) define multi-step reasoning/tools → Backend coordinates tool calls (local tools, web search, MCP).
    2. Optional sandbox executor runs untrusted steps safely → results flow back to the agent and then to the user.

- **Key technologies and frameworks**
  - **Frontend**: React 18, UmiJS, Ant Design, Radix UI, Tailwind.
  - **Backend**: Python, Flask, Flasgger (Swagger), Flask-Login/Session/Mail, Peewee ORM; served by Werkzeug (dev) behind Nginx.
  - **RAG pipeline**: Custom modules in `rag/` for chunking, embedding, retrieval; supports multiple doc engines; reranking with BAAI/bge.
  - **Parsers/vision**: `deepdoc/` with PDF/Office parsing and OCR/vision helpers.
  - **Datastores**: MySQL (metadata), Redis (locks), MinIO (objects), Elasticsearch/OpenSearch or Infinity (search+vector).
  - **Ops**: Docker Compose, Helm charts for K8s; config under `conf/` and env files.

### Part 2: Codebase Organization (Directory & Module Structure)

- `api/`: Flask app, route registration, REST APIs, DB models, services, runtime configuration, and server entrypoint.
- `deepdoc/`: Document parsing/understanding (PDF/Office/image), layout/vision utilities, and parser configs.
- `rag/`: Core RAG logic: chunking, embeddings, retrieval, reranking, prompts, task execution, utilities.
- `web/`: Frontend React app (UmiJS) with pages, components, state, and tests.
- `agent/`: Agent framework, components, tools integration, templates, and test clients.
- `agentic_reasoning/`: Higher-level deep research/reasoning flows and prompts.
- `graphrag/`: Graph-based RAG utilities (entity resolution, search strategies, prompts).
- `sdk/`: Python SDK for programmatic access to RAGFlow APIs; tests/examples included.
- `sandbox/`: Isolated executor manager (FastAPI) and runtime for secure tool/code execution.
- `mcp/`: Model Context Protocol server/client utilities for integrating external MCP servers.
- `plugin/`: Plugin interfaces and plugin manager for extending LLM tools and capabilities.
- `api/db/`: ORM models, migrations, and DB service utilities for metadata persistence.
- `api/apps/`: Modular API route groups (apps) and SDK-style endpoints.
- `docs/`: User/developer documentation, guides, references, and release notes.
- `docker/`: Compose files, Nginx configs, entrypoint scripts, and service templates.
- `helm/`: Kubernetes charts and templates for deploying RAGFlow services.
- `conf/`: Runtime configuration templates (service_conf, LLM factories, mappings).
- `intergrations/`: Integrations (e.g., WeChat plugin, Chrome extension).
- `example/`: Example scripts (HTTP dataset ingestion), sample usage.
- `test/`: End-to-end and API tests (web API, HTTP API, SDK API).
- `agent/templates/`: Predefined agent workflows and assistants as JSON templates.
- `download_deps.py`: Helper script to fetch/download model or data dependencies.
- `Dockerfile*`: Container build definitions for different flavors.
- `README*.md`: Multilingual project documentation.
- `uv.lock`, `pyproject.toml`: Python dependency lock and project metadata.

- Top 3 directories to focus on first:
  - **`api/`**: Understand routing, request lifecycle, services, DB models, and configuration—this is the orchestration layer.
  - **`rag/`**: Learn the end-to-end RAG pipeline: chunking, embedding, indexing, retrieval, reranking, and answer generation.
  - **`deepdoc/`**: See how documents are parsed and structured prior to chunking and indexing; critical for ingestion quality.
