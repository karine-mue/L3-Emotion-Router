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
---
## 🛠 Troubleshooting / Technical Notes
開発過程で直面した「LLMを冷徹なスイッチとして動かすための」物理的な障壁とその解決策。
 * 1. TTY Hooking & Infinite REPL Loop
   * Issue: llama-cliがGGUF内のチャットテンプレートを検出すると、自動的に対話モード（REPL）を起動してしまい、スクリプトが停止（入力待ち）する。
   * Solution: llama-cli ... < /dev/null とすることで、標準入力に物理的なEOF（終了）を送り込み、プロセスの自律終了を強制。さらに --override-kv "tokenizer.chat_template=str:" でテンプレート定義をメモリ上で上書きし、対話モードのトリガー自体を消去。
 * 2. Terminal Wrapping & GBNF Parser Failure
   * Issue: cat << 'EOF' (heredoc) を用いたファイル生成時、スマホターミナルの画面折り返し位置に不可視の改行コードが混入し、GBNFパーサーが expecting name エラーでクラッシュする。
   * Solution: エディタやheredocを介さず、echo '...' >> schema.gbnf のように1行ずつの直列追記（Append）方式でファイルを物理構築し、バイナリレベルの整合性を確保。
 * 3. GBNF Naming Convention
   * Issue: llama.cpp のGBNFパーサーのバージョンにより、ルール名に含まれるアンダースコア（_）やハイフン（-）がパースミスを誘発する。
   * Solution: ルール名を tasktype, safestring のように英数字のみに結合し、命名規則に依存しない堅牢な金型を作成。
 * 4. Missing "Generation" Task
   * Issue: Qwen3.5-4Bは極めて高精度にタスクを分類するが、用意した選択肢（分析・抽出等）に「生成」がない場合、思考（reasoning）の過程で「適切なカテゴリがない」と自家中毒（ループや思考の肥大化）を起こす。
   * Solution: Enumに "generation" を追加し、モデルに適切な出口（Routing）を提供することで推論を安定化。
 * 5. Dynamic Response Fields (Content vs Reasoning)
   * Issue: 推論モデル（Thinking model）をサーバー経由で叩くと、GBNFで拘束した出力が .choices[0].message.content ではなく、思考用フィールドである .choices[0].message.reasoning_content に格納される。
   * Solution: jq を用いて、両方のフィールドをフォールバック参照する抽出ロジック（if .content == "" then .reasoning_content else .content end）を実装。
