#!/usr/bin/env bash
# <summary>
# Sync OmniRoute's /v1/models catalog into ~/.pi/agent/models.json.
# Keeps chat models only (drops aihorde image-gen and veo-free video),
# maps context_length/max_output_tokens/capabilities/pricing onto pi's
# model schema. Re-run after OmniRoute gains or loses upstream providers.
# Requires: curl, jq, API_OMNIROUTE_KEY env, OmniRoute on OMNIR_OUTE_URL.
# </summary>
set -euo pipefail

OMNIROUTE_URL="${OMNIROUTE_URL:-http://localhost:20128}"
OUT="${1:-$HOME/.pi/agent/models.json}"

curl -sf -m 15 -H "Authorization: Bearer $API_OMNIROUTE_KEY" \
  "$OMNIROUTE_URL/v1/models" | jq '
  {
    "$schema": "https://pi.dev/schemas/models.schema.json",
    providers: {
      omniroute: {
        name: "OmniRoute",
        baseUrl: "http://localhost:20128/v1",
        api: "openai-completions",
        apiKey: "$API_OMNIROUTE_KEY",
        authHeader: true,
        compat: {
          supportsStore: false,
          maxTokensField: "max_tokens"
        },
        models: [
          .data[]
          | select(.id | (startswith("aihorde/") or startswith("veo-free/")) | not)
          | {
              id,
              name: (.name // .id),
              reasoning: ((.capabilities.reasoning // .capabilities.thinking // .thinking // .supportsThinking // false)),
              input: (
                [(.input_modalities // ["text"])[] | select(. == "text" or . == "image")]
                | if length == 0 then ["text"] else . end
              ),
              cost: (
                if .pricing then
                  { input: (.pricing.input // 0), output: (.pricing.output // 0),
                    cacheRead: (.pricing.cached // 0), cacheWrite: 0 }
                else
                  { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
                end
              ),
              contextWindow: (.context_length // 128000),
              maxTokens: ([(.max_output_tokens // 16384), 65536] | min)
            }
        ] | sort_by(.id)
      }
    }
  }' > "$OUT"

echo "wrote $(jq '.providers.omniroute.models | length' "$OUT") models -> $OUT"
