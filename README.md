# L3-Emotion-Router
A Termux-based pre-processing layer that routes human intent into structured JSON payloads. Bypasses LLM empathy filters by isolating emotional context into metadata.

## Architecture

```
==========================================================================
                     L3-Emotion-Router Architecture
==========================================================================

   [ Human Layer ]
          |
          v  (Emotional/Narrative Input)
   +---------------------------------------+
   |  Android Clipboard (Pixel / Termux)   |
   +---------------------------------------+
          |
          | (termux-clipboard-get)
          v
   +--------------------------------------------------------------------+
   |  [ L1/L2: LOCAL EDGE (Termux / Pixel RAM) ]                        |
   |                                                                    |
   |   1. INPUT SANITIZER (jq -Rs)                                      |
   |      - Convert raw text into safe JSON-string                      |
   |                                                                    |
   |   2. PROMPT INJECTOR (printf -> /tmp/prompt)                       |
   |      - Bind System/User/Assistant ChatML templates                 |
   |                                                                    |
   |   3. INFERENCE ENGINE (llama-server + Qwen3.5-4B)                  |
   |      - < /dev/null  : Suffocate TTY (Bypass REPL mode)             |
   |      - --override-kv: Wipe chat_template (Disable REPL)            |
   |      - --grammar    : Enforce GBNF (EBNF Grammar Plane)            |
   |                                                                    |
   |   4. OUTPUT FILTER (sed + jq)                                      |
   |      - Strip residual tokens (<|im_end|>)                          |
   |      - Map fields (content / reasoning_content)                    |
   |                                                                    |
   +--------------------------------------------------------------------+
          |
          | (Sanitized JSON Payload)
          v
   +--------------------------------------------------------------------+
   |  [ L3: CLOUD (OpenAI API / gpt-4o) ]                               |
   |                                                                    |
   |   - Input: Pre-processed { intent, constraints, note }             |
   |   - Logic: Execute purely based on intent/constraints              |
   |   - Bypass: GPT's RLHF/Empathy layers are neutralized              |
   |                                                                    |
   +--------------------------------------------------------------------+
          |
          v (Pure Computation Result)
   [ Final Result (e.g. Recipe / Code) ]

==========================================================================

```
