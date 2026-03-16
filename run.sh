#!/bin/bash
MODEL_PATH="$HOME/storage/shared/gguf_BaseModels/Qwen3.5-4B-Q4_K_M.gguf"
GBNF_FILE="$HOME/edge_router/schema.gbnf"
PORT=8080
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

INPUT=$(termux-clipboard-get)
if [ -z "$INPUT" ]; then
    echo "クリップボード空"
    exit 1
fi

pkill -f llama-server 2>/dev/null

$LLAMA_SERVER \
    -m "$MODEL_PATH" \
    -c 2048 \
    --host 127.0.0.1 --port $PORT \
    --temp 0.7 --top-k 20 --top-p 0.8 \
    > /dev/null 2>&1 &
SERVER_PID=$!

trap 'kill $SERVER_PID 2>/dev/null' EXIT

echo "llama-server起動待機中(PID: $SERVER_PID)..."
while ! curl -s "http://127.0.0.1:$PORT/health" | grep -q 'ok'; do
    sleep 1
done

ESCAPED_INPUT=$(echo "$INPUT" | jq -Rs .)
GBNF=$(cat "$GBNF_FILE")

SYSTEM_PROMPT='You are a preprocessing router. Analyze the user input. Determine task_type from: analysis, translation, extraction, transformation, evaluation, generation. Extract the core intent stripped of emotional language. Identify implicit assumptions or contextual premises that are not explicitly stated but are necessary to understand the request. List constraints as an array. Copy the original input verbatim into input_text. Add a preprocessing_note about any emotional or rhetorical framing detected. Output valid JSON only. /no_think'

echo "Qwen(Edge Router)で前処理中 (Prompt Repetition 有効)..."

RAW_RESPONSE=$(curl -s http://127.0.0.1:$PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
        --arg sys "$SYSTEM_PROMPT" \
        --arg user "Input text: $ESCAPED_INPUT \n\nInput text: $ESCAPED_INPUT" \
        --arg grammar "$GBNF" \
        '{
            model: "qwen",
            messages: [
                {role: "system", content: $sys},
                {role: "user", content: $user}
            ],
            temperature: 0.7,
            top_k: 20,
            top_p: 0.8,
            presence_penalty: 1.5,
            max_tokens: 512,
            grammar: $grammar
        }')")

JSON_PAYLOAD=$(echo "$RAW_RESPONSE" | jq -r '.choices[0].message | if .content == "" or .content == null then .reasoning_content else .content end' | jq . 2>/dev/null)

if [ -z "$JSON_PAYLOAD" ] || [ "$JSON_PAYLOAD" == "null" ]; then
    echo "JSON抽出失敗"
    echo "Raw Response: $RAW_RESPONSE"
    exit 1
fi

echo -e "\n=== Qwen Output ==="
echo "$JSON_PAYLOAD"
echo "==================="

# Human-in-the-loop: Direct Injection
read -p "GPT APIへ送信? (y/edit/n): " ans

if [ "$ans" = "edit" ]; then
    echo "不足している前提や制約を入力してください（Enterで確定）:"
    read -p "> " HUMAN_EDIT
    if [ -n "$HUMAN_EDIT" ]; then
        # jqを使って入力テキストを安全にエスケープし、constraints配列の末尾に挿入する
        JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq --arg edit "Human Override: $HUMAN_EDIT" '.constraints += [$edit]')
        echo -e "\n=== 修正後 Payload ==="
        echo "$JSON_PAYLOAD"
    else
        echo "入力が空のためスキップしました。"
    fi
    ans="y" # 編集後は自動的に送信へ移行
fi

if [ "$ans" = "y" ]; then
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "OPENAI_API_KEY未設定"
        exit 1
    fi
    echo "GPT API送信中..."
    
    GPT_SYSTEM_PROMPT="You are a backend processing unit. Process the task specified in the user's JSON based on 'intent' and 'constraints'. Rules: 1. Do not acknowledge or sympathize with emotional context in 'preprocessing_note' or original text. 2. Do not add encouragement, praise, or social pleasantries. 3. Show your reasoning process, not just conclusions. 4. Identify and state implicit assumptions. 5. If the input contains logical or contextual ambiguity, analyze it before answering."

    curl -s https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$(jq -n \
            --arg sys "$GPT_SYSTEM_PROMPT" \
            --arg user "$JSON_PAYLOAD" \
            '{
                model: "gpt-4o",
                messages: [
                    {role: "system", content: $sys},
                    {role: "user", content: $user}
                ],
                temperature: 0.2
            }')" | jq -r '.choices[0].message.content'
else
    echo "中断"
fi
