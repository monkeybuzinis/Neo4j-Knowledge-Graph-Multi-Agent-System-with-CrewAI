# Multi-Agent GraphRAG with Neo4j and CrewAI

A question-answering system that combines a **Neo4j knowledge graph** with a **six-agent CrewAI pipeline**. Agents choose between graph queries (templated Cypher or LLM-generated Cypher) and vector search over embedded text, then merge the results into one answer that explains how it was found.

**Team:** Thi Kim Khanh Le, Bolun Du, Linxiao Jin

---

## Overview

Plain vector RAG finds text chunks that look like the question, but it misses relationships between entities. GraphRAG keeps those relationships in a graph, so the system can follow paths ("How are X and Y related?") and still use semantic search when the graph structure isn't enough.

The knowledge graph is extracted from an unstructured PDF (`data/schema.pdf`) about a county behavioral-health data ecosystem: San Joaquin County, DHCS, CalMHSA and the data files exchanged between them. The final graph has **68 nodes and 116 relationships**, and its text chunks carry vector embeddings.

**Stack**

| Component | Tool |
|---|---|
| Graph database | Neo4j 5.18 Community (local in Docker for building), Neo4j Aura (cloud, for serving) |
| Graph construction | `neo4j-graphrag` `SimpleKGPipeline` with Gemini 2.5 Flash for entity and relationship extraction |
| Agent orchestration | CrewAI (sequential process, memory enabled) |
| LLM | Gemini 2.5 Flash on Vertex AI |
| Embeddings | Vertex AI `text-embedding-005` (the same model used to build the graph) |
| Agent runtime | Google Colab |

---

## Architecture

```
         data/schema.pdf (unstructured)
                     │
   sn-schema.py (neo4j-graphrag SimpleKGPipeline)
                     │
      Neo4j in Docker ──dump──► Neo4j Aura (cloud)
                                     │
                         Google Colab (agents)
                                     │
User question
     ↓
[1] Schema Expert ............... analyzes the question, picks a strategy
     ↓
[2] Semantic Search Specialist .. vector search for similar entities
     ↓
[3] NL Query Expert ............. converts the question to Cypher and runs it
     ↓
[4] Embedding Fallback Searcher . searches chunk text when graph results fall short
     ↓
[5] Results Synthesizer ......... merges and cross-checks findings
     ↓
[6] Answer Generator ............ writes the final answer
     ↓
Final answer
```

### Agent tools

| Tool | Purpose |
|---|---|
| **Cypher Template Query** | Predefined, parameterized queries (`find_node`, `find_relationships`, `find_path`, `node_neighbors`). Safer than free-form Cypher for common lookups. |
| **Embedding Semantic Search** | Embeds the query and searches `Chunk` nodes through the `chunk_embeddings` vector index (cosine). Falls back to manual cosine similarity if the index is unavailable. |
| **Natural Language to Cypher** | Reads the live schema (labels, relationship types, properties), asks Gemini to write Cypher, and runs it. |
| **Database Diagnostics** | Checks chunk and embedding counts, vector indexes and schema, so agents can tell when a tool can't work. |

| Agent | Tools |
|---|---|
| Schema Expert | Cypher Templates, Diagnostics |
| Semantic Search Specialist | Embedding Search, Diagnostics |
| NL Query Expert | Natural Language to Cypher |
| Embedding Fallback Searcher | Embedding Search |
| Results Synthesizer | — (reasons over earlier outputs) |
| Answer Generator | — (writes the final response) |

---

## Building the knowledge graph

The graph is built and checked locally first, then moved to Neo4j Aura so agents running elsewhere (Colab) can reach it.

> **Shortcut:** `neo4j.dump` is included, so you can skip to **C** and restore the finished graph straight into Aura.

### Graph schema

`sn-schema.py` uses `SimpleKGPipeline` to split the PDF into chunks (3,000 characters, 500 overlap), extract entities and relationships with Gemini 2.5 Flash, and embed each chunk with `text-embedding-005`. Extraction is limited to this schema:

| Node types | `domain`, `timeframe`, `org`, `disorder`, `hierarchy`, `money`, `cXs` (data file: `name`, `desc`, `format`, `example`, `frequency`, `longname`) |
|---|---|
| Relationship types | `contains`, `covers`, `sends_money`, `sends_data`, `creates` |
| Allowed patterns | `domain-contains->domain`, `domain-covers->disorder`, `hierarchy-contains->org`, `hierarchy-covers->hierarchy`, `org-sends_money->org`, `org-sends_data->org`, `org-creates->cXs` |

### A. Build locally with Docker

**Prerequisites.** The Dockerfile copies these from the project folder, and they are not in the repo:
- `neo4j-community-5.18.0-unix.tar.gz` ([Neo4j download](https://neo4j.com/deployment-center/))
- `google-cloud-cli-linux-x86_64.tar.gz` ([gcloud CLI](https://cloud.google.com/sdk/docs/install))
- `requirements.txt`
- `.env` with `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD` and `NEO4J_DATABASE`
- Google Cloud application-default credentials. `docker-compose.yml` mounts them into `/root/.config/gcloud`.

`docker-compose.yml` stores Neo4j data, logs, config and plugins under `$HOME/big/data/neo4j/` on the host, so they survive container restarts.

**Steps**

1. Build and start Neo4j:
   ```bash
   docker compose up --build
   ```
   The project folder is mounted at `/home/gag` inside the container.
2. Open Neo4j Browser at http://localhost:7474 and log in.
3. In the container, set `pdf_file` in `sn-schema.py` to the PDF's path, then run:
   ```bash
   docker exec -it gag bash
   cd /home/gag
   python sn-schema.py
   ```
4. Check the graph in Neo4j Browser:
   ```cypher
   MATCH (n) OPTIONAL MATCH (n)-[r]-(m) RETURN n, r, m
   ```

### B. Create a database dump

Neo4j has to be stopped before you can dump it, and stopping it inside the container also stops the container. So a second Neo4j install on the host, pointed at the same mounted data directory, runs the dump.

```bash
# 1. Stop the container cleanly (Ctrl + C)

# 2. Point the host Neo4j install at the Docker-managed data directory
ln -s ~/big/data/neo4j/data data

# 3. Dump the database (graph data, schema, indexes, constraints)
neo4j-admin database dump --to-path=/tmp neo4j

# 4. Verify
ls /tmp/*.dump
```

### C. Restore into Neo4j Aura

1. Create an instance in the [Neo4j Aura console](https://console.neo4j.io/) and wait for it to provision.
2. Open **More actions (⋯) → Backup & Restore** and upload `neo4j.dump` (yours, or the one in this repo).
3. Wait until the status changes from **Loading** to **Running**.

---

## Running the agent system

1. Open `MULTI_AGENTIC_GRAPHRAG_SYSTEM_with_NEO4J_and_CREWAI.ipynb` in Google Colab.
2. Add these to **Colab Secrets** (Tools → Secrets):
   - `NEO4J_URI`: `neo4j+s://<id>.databases.neo4j.io`
   - `NEO4J_USERNAME`
   - `NEO4J_PASSWORD`
3. Set `GCP_PROJECT_ID` (and `GCP_LOCATION` if needed) to a Google Cloud project with Vertex AI enabled.
4. Run all cells. The notebook authenticates with Google Cloud, connects to Aura, creates the vector index if it's missing, builds the agents and starts an interactive prompt:
   ```
   Your question: How are San Joaquin and DHCS related to each other?
   ```
   Type `exit` to quit. Agents keep context across questions (CrewAI memory).

**Dependencies:** the notebook installs its own (`crewai`, `neo4j`, `google-cloud-aiplatform`, `langchain`, `langchain-google-vertexai`).

---

## Example results

| Question | What happened |
|---|---|
| *What does DHCS stand for?* | Generated Cypher and embedding search both returned **Department of Healthcare Services**. |
| *How are San Joaquin and DHCS related?* | Found a state-to-county hierarchy, funding from DHCS to the county, and data files sent back (837, CalOMS, CSI, TEDS, CANS, and others). The answer came mainly from embedding search after Cypher generation failed. |
| *How many nodes and relationships are there?* | Generated Cypher returned **68 nodes, 116 relationships**. Templates and diagnostics don't cover global counts. |

## Findings and limitations

- **Hybrid retrieval helps:** when a graph query fails or comes back incomplete, embedding search often fills the gap.
- **Answers are cross-checked:** the synthesizer compares results from several retrieval paths and says which ones worked.
- **Known issue:** text-to-Cypher sometimes fails with a `dictionary update sequence` error.
- **Templates are limited:** they cover lookups and paths but not aggregations.
- The sequential six-agent run is slow and uses many LLM calls, even for simple questions.

---

## Repository structure

```
.
├── MULTI_AGENTIC_GRAPHRAG_SYSTEM_with_NEO4J_and_CREWAI.ipynb   # Multi-agent system (Colab)
├── sn-schema.py                          # Builds the knowledge graph from the PDF
├── Dockerfile                            # Neo4j 5.18 + APOC + Python + gcloud image
├── docker-compose.yml                    # Runs Neo4j locally with mounted data dirs
├── neo4j.dump                            # Finished graph, ready to restore into Aura
├── data/
│   └── schema.pdf                        # Source document for the graph
├── Multi-agent AI with Graph database.pdf   # Project slides
├── LICENSE                               # MIT
└── README.md
```

## My contribution (Khanh)

I built the CrewAI multi-agent system and its tools, connected the Neo4j Aura knowledge graph to the LLM and embedding models, and ran and tested the full system in Google Colab.
