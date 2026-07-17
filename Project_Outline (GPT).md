# Recall — A User-Controlled AI Memory Layer

## Overview

Recall is a browser extension and app that lets users save exactly what they want to remember—such as a paragraph, figure, image, equation, webpage, or note.

Instead of letting AI decide what matters through automatic summaries, Recall follows a different principle:

> The user chooses what to remember. AI organizes and retrieves it.

For the hackathon MVP, Recall focuses on researchers reading papers.

---

## Problem

Researchers often find a few important sentences, figures, or methods inside long papers. Existing tools save the full paper or generate a general summary, but they often lose:

* the exact information that mattered;
* why the user saved it;
* its original context and source;
* its relationship to other saved findings.

Over time, bookmarks, screenshots, and notes become difficult to search and organize.

---

## Solution

While reading a paper, the user highlights content and clicks **Save to Recall**.

Recall automatically stores:

* the selected content;
* paper title, URL, page, and section;
* surrounding context;
* an optional user note;
* inferred categories such as finding, method, limitation, contradiction, or future experiment;
* related saved memories.

Users can later ask:

* “What have I saved about CNT sensor hysteresis?”
* “Show methods using RMS windows.”
* “Which saved papers disagree about this mechanism?”
* “Find evidence relevant to my current experiment.”

Every answer links back to the original saved source.

---

## Key Features

### Intentional Capture

Save highlighted text, figures, images, or notes directly from the browser.

### “Why I Saved This”

Recall records the purpose of a memory, such as:

* useful method;
* supporting evidence;
* contradiction;
* future citation;
* research idea;
* limitation.

### Automatic Organization

AI generates tags, collections, concepts, and source metadata.

### Connected Memory

Recall identifies similar, supporting, contradictory, or duplicate memories.

### Grounded Search and Chat

Users search their saved knowledge using natural language. Responses cite exact saved passages.

### Storage Optimization

Recall suggests duplicate merging, grouping, or archiving, but never deletes content without approval.

---

## MVP Scope

The hackathon prototype should support one complete workflow:

1. Highlight text on a webpage or browser PDF.
2. Click **Save to Recall**.
3. Add an optional note or memory type.
4. Automatically extract metadata and concepts.
5. Display related saved memories.
6. Search or chat across all captures.
7. Open the original source from every result.

Support only:

* webpage text;
* PDF text;
* image or figure clips;
* manual notes.

Photo libraries, email, video, and universal file storage remain future expansions.

---

## Technical Architecture

```text
Browser Extension
        ↓
Capture API
        ↓
AI Metadata and Intent Extraction
        ↓
PostgreSQL + Vector Search
        ↓
Relationship Detection
        ↓
Web App and ChatGPT App
```

### Suggested Stack

* Next.js and TypeScript
* Chrome Manifest V3 extension
* Supabase authentication and PostgreSQL
* pgvector for semantic search
* OpenAI API for structured extraction and grounded answers
* MCP server for ChatGPT integration
* Vercel deployment

---

## Core Data Model

Each memory contains:

```ts
type Memory = {
  id: string;
  originalContent: string;
  surroundingContext?: string;
  userNote?: string;
  memoryTypes: string[];
  concepts: string[];
  sourceUrl?: string;
  sourceTitle?: string;
  pageNumber?: number;
  collection?: string;
  createdAt: string;
};
```

Relationships between memories include:

```ts
type Relationship =
  | "similar"
  | "supports"
  | "contradicts"
  | "extends"
  | "duplicate"
  | "related";
```

---

## Repository Template

```text
recall/
├── apps/
│   ├── web/
│   ├── extension/
│   └── mcp-server/
├── packages/
│   ├── database/
│   ├── ai/
│   ├── retrieval/
│   └── shared/
├── tests/
├── scripts/
└── docs/
```

Important modules:

```text
ai/
├── enrich-memory.ts
├── classify-relationship.ts
└── answer-from-memory.ts

retrieval/
├── semantic-search.ts
├── keyword-search.ts
└── hybrid-ranker.ts
```

---

## Demo

1. Open a research paper.

2. Highlight a sentence about CNT sensor hysteresis.

3. Save it with one click.

4. Show automatically extracted source information and categories.

5. Show a related memory from another paper.

6. Ask:

   “What explanations have I saved for CNT hysteresis?”

7. Display a grounded comparison with links to each source.

8. Show a duplicate-memory merge suggestion.

---

## Why It Is Different

Recall is not another summarizer or bookmark manager.

A bookmark stores a location.

Recall stores:

[
\text{Content} + \text{Source} + \text{Reason for saving}
]

The system does not automatically record everything the user sees. The user explicitly controls what enters memory, while AI handles organization, connection, retrieval, and cleanup.

---

## Long-Term Vision

Recall can expand from research papers to:

* screenshots and photos;
* code and documentation;
* videos and audio;
* email and messages;
* personal and professional documents.

The result is a unified personal memory layer across applications.

---

## Tagline

> Save what matters. Recall it with context.
