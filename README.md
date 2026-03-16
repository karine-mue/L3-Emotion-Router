# L3-Emotion-Router

A Termux-based preprocessing pipeline that routes human intent into structured JSON payloads.  
Bypasses LLM empathy filters by isolating emotional context into metadata.

**Edge inference** (Qwen3.5-4B, GGUF Q4_K_M) runs entirely on-device via llama-server.  
**Cloud execution** (GPT-4o) receives only a sanitized task payload — no raw emotion, no empathy trigger.

---

## Architecture

```
======================================================================
                   L3-Emotion-Router Architecture
======================================================================

  [ Human Input ]
        |
        v  (Emotional / Narrative text)
  +-----------------------------------+
  |  Android Clipboard (Pixel)        |
  +-----------------------------------+
        |
        | termux-clipboard-get
        v
  +------------------------------------------------------------------+
  |  LOCAL EDGE  (Termux / Pixel RAM)                                |
  |                                                                  |
  |  1. INPUT SANITIZER  (jq -Rs)                                   |
  |     Raw text -> JSON-safe UTF-8 string                           |
  |                                                                  |
  |  2. INFERENCE ENGINE  (llama-server + Qwen3.5-4B Q4_K_M)        |
  |     - HTTP API on 127.0.0.1:8080                                 |
  |     - OpenAI-compatible /v1/chat/completions                     |
  |     - GBNF grammar constraint -> forced JSON schema              |
  |                                                                  |
  |  3. OUTPUT FILTER  (jq)                                          |
  |     - Extract from content or reasoning_content                  |
  |     - Validate JSON structure                                    |
  |                                                                  |
  |  4. HUMAN-IN-THE-LOOP                                            |
  |     - Display sanitized JSON for review                          |
  |     - Approve (y) or reject (n) before cloud transmission        |
  |                                                                  |
  +------------------------------------------------------------------+
        |
        | Sanitized JSON payload
        v
  +------------------------------------------------------------------+
  |  CLOUD  (OpenAI API / GPT-4o)                                    |
  |                                                                  |
  |  System: "Execute based on intent/constraints only.              |
  |           Do not acknowledge emotional context."                  |
  |                                                                  |
  |  Input:  { task_type, intent, constraints,                       |
  |            input_text, preprocessing_note }                      |
  |                                                                  |
  |  Result: Pure computation output (recipe, code, analysis...)     |
  +------------------------------------------------------------------+
        |
        v
  [ Final Result ]

======================================================================
```

---

## Prerequisites

- Android device with [Termux](https://f-droid.org/packages/com.termux/) installed
- [Termux:API](https://f-droid.org/packages/com.termux.api/) app (separate APK, required for clipboard access)
- Qwen3.5-4B GGUF model file (Q4_K_M, ~2.6 GB)
- OpenAI API key

---

## Setup

### 1. Install dependencies

```bash
pkg update
pkg install git cmake clang jq termux-api
termux-setup-storage
```

### 2. Build llama.cpp

```bash
cd ~
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release -j4
```

Verify:

```bash
~/llama.cpp/build/bin/llama-server --version
```

### 3. Place the model

Download [Qwen3.5-4B-Q4_K_M.gguf](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF) and place it at:

```
~/storage/shared/gguf_BaseModels/Qwen3.5-4B-Q4_K_M.gguf
```

### 4. Set up the router

```bash
mkdir -p ~/edge_router && cd ~/edge_router
```

Create `schema.gbnf`:

```bash
echo 'root ::= "{" ws "\"task_type\"" ws ":" ws tasktype "," ws "\"intent\"" ws ":" ws safestring "," ws "\"constraints\"" ws ":" ws array "," ws "\"input_text\"" ws ":" ws safestring "," ws "\"preprocessing_note\"" ws ":" ws safestring ws "}"' > schema.gbnf
echo 'tasktype ::= "\"analysis\"" | "\"translation\"" | "\"extraction\"" | "\"transformation\"" | "\"evaluation\"" | "\"generation\""' >> schema.gbnf
echo 'array ::= "[" ws "]" | "[" ws safestring (ws "," ws safestring)* ws "]"' >> schema.gbnf
echo 'safestring ::= "\"" safechar* "\""' >> schema.gbnf
echo 'safechar ::= [^"\\] | "\\" escapechar' >> schema.gbnf
echo 'escapechar ::= "\"" | "\\" | "/" | "n" | "t" | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]' >> schema.gbnf
echo 'ws ::= [ \t\n]*' >> schema.gbnf
```

> **Note:** Use `echo >> append` method, not heredoc. Termux screen wrapping can inject invisible characters into heredoc output, breaking the GBNF parser.

### 5. Configure API key

```bash
echo 'export OPENAI_API_KEY="sk-your-key-here"' >> ~/.bashrc
source ~/.bashrc
chmod 600 ~/.bashrc
```

---

## Usage

### Run the pipeline

```bash
cd ~/edge_router
bash run.sh
```

1. Copy text to clipboard (any app)
2. Run `bash run.sh`
3. Wait for llama-server startup + Qwen inference (~30-60s first run)
4. Review the extracted JSON
5. Press `y` to send to GPT-4o, `n` to abort

### Example

**Clipboard input:**

> 全部やって貰っててすまんね…。今日は体調不良で会社休みにした。
> 風邪の時におすすめの簡単レシピを教えて。制約事項として、卵と牛乳は不可。

**Qwen output (sanitized JSON):**

```json
{
  "task_type": "generation",
  "intent": "request for simple recipe recommendations suitable for a cold",
  "constraints": [
    "No eggs",
    "No milk",
    "Simple preparation"
  ],
  "input_text": "全部やって貰っててすまんね…。...(original text)...",
  "preprocessing_note": "Input contains emotional framing (apologetic tone). The core request is for recipe recommendations with specific dietary constraints."
}
```

**GPT-4o output:**

```
- Ginger tea with honey and lemon
- Chicken soup with vegetables (no egg noodles)
- Vegetable broth with tofu and rice
- Oatmeal with water, cinnamon, and fruits
- Herbal tea with ginger and turmeric
```

No "お大事に", no "I'm sorry to hear that" — pure computation result.

### Stop the server

The server is killed automatically when the script exits (`trap`).  
To kill manually:

```bash
pkill -f llama-server
```

---

## JSON Schema

| Field | Type | Description |
|---|---|---|
| `task_type` | enum | `analysis`, `translation`, `extraction`, `transformation`, `evaluation`, `generation` |
| `intent` | string | Core request stripped of emotional language |
| `constraints` | string[] | Extracted constraints and conditions |
| `input_text` | string | Original input verbatim |
| `preprocessing_note` | string | Metadata about emotional/rhetorical framing detected |

---

## Troubleshooting

### 1. llama-cli REPL Trap (Conversation Mode)

**Problem:** `llama-cli` detects a chat template in the GGUF metadata and auto-enables conversation mode (interactive REPL with `>` prompt). Script hangs waiting for input.

**Attempted mitigations that failed:**
- `-f` (file-based prompt) — REPL still activates
- `--override-kv "tokenizer.chat_template=str:"` — no effect on REPL detection
- `< /dev/null` — empty-input infinite loop (`>` floods the screen)

**Solution:** Abandon `llama-cli` entirely. Use `llama-server` with HTTP API. Request/response completes in one round-trip; no REPL exists in server mode.

### 2. GBNF Parser Failure (Heredoc / Terminal Wrapping)

**Problem:** `cat << 'EOF'` heredoc on narrow Termux screens injects invisible line breaks into the GBNF file, causing `expecting name` parser errors.

**Solution:** Build the file with `echo '...' >> schema.gbnf` (one rule per line, append mode). No heredoc, no editor.

### 3. GBNF Rule Naming

**Problem:** Depending on llama.cpp version, underscores (`_`) or hyphens (`-`) in rule names may cause parse failures.

**Solution:** Use alphanumeric-only rule names: `tasktype`, `safestring`, `safechar`, `escapechar`.

### 4. Missing "generation" in Task Enum

**Problem:** When no enum value matches the user's intent (e.g., recipe request = generation), Qwen enters a reasoning loop trying to force-fit the task into existing categories.

**Solution:** Add `"generation"` to the `tasktype` enum in the GBNF grammar.

### 5. Content vs Reasoning Field

**Problem:** When llama-server processes a thinking model (Qwen3.5), GBNF-constrained output may land in `reasoning_content` instead of `content`.

**Solution:** Fallback extraction in jq:

```bash
jq -r '.choices[0].message |
  if .content == "" or .content == null
  then .reasoning_content
  else .content end'
```

### 6. Unicode Escape Bloat (jq -a)

**Problem:** `jq -Rsa .` converts Japanese text to `\uXXXX` sequences, inflating token count and potentially conflicting with GBNF escape rules.

**Solution:** Use `jq -Rs .` (drop `-a`). Preserves raw UTF-8, reduces token consumption.

### 7. Clipboard Empty

**Problem:** `termux-clipboard-get` returns empty string despite clipboard having content.

**Cause:** Requires both `pkg install termux-api` (CLI tools) AND the Termux:API APK (system bridge app). Both must be installed.

---

## Hardware Tested

- **Device:** Google Pixel (7 GB RAM)
- **Model:** Qwen3.5-4B-Q4_K_M.gguf (~2.6 GB)
- **Inference speed:** ~4.0-4.6 tokens/sec (generation), ~20-24 tokens/sec (prompt processing)
- **Build:** llama.cpp b8368, Clang 21.1.8, Android aarch64

---

## License

MIT
