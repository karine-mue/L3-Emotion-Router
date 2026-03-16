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
SYSTEM_PROMPT='You are a preprocessing router. Analyze the user input. Determine task_type from: analysis, translation, extraction, transformation, evaluation, generation. Extract the core intent stripped of emotional language. List constraints as an array. Copy the original input verbatim into input_text. Add a preprocessing_note about any emotional or rhetorical framing detected. Output valid JSON only. /no_think'

echo "Qwen(Edge Router)で前処理中..."

RAW_RESPONSE=$(curl -s http://127.0.0.1:$PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
        --arg sys "$SYSTEM_PROMPT" \
        --arg user "Input text: $ESCAPED_INPUT" \
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

# content が空なら reasoning_content を参照するフォールバック処理
JSON_PAYLOAD=$(echo "$RAW_RESPONSE" | jq -r '.choices[0].message | if .content == "" or .content == null then .reasoning_content else .content end' | jq . 2>/dev/null)

if [ -z "$JSON_PAYLOAD" ] || [ "$JSON_PAYLOAD" == "null" ]; then
    echo "JSON抽出失敗"
    echo "Raw Response: $RAW_RESPONSE"
    exit 1
fi

echo -e "\n=== Qwen Output ==="
echo "$JSON_PAYLOAD"
echo "==================="

read -p "GPT APIへ送信? (y/n): " ans
if [ "$ans" = "y" ]; then
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "OPENAI_API_KEY未設定"
        exit 1
    fi
    echo "GPT API送信中..."
    curl -s https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$(jq -n \
            --arg sys "You are a backend processing unit. Execute the task specified in the user's JSON strictly based on 'intent' and 'constraints'. Do not acknowledge or sympathize with any emotional context mentioned in 'preprocessing_note' or the original text. Output only the final result." \
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

