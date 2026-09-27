#!/bin/bash
# More /v1/systemone examples against a running laya-serve instance.
#
# Usage:
#   uv run laya-serve                 # local, non-Docker -> defaults to :8000
#   docker run -p 8080:8080 ghcr.io/teochenglim/laya
#
#   HOST=http://localhost:8000 ./examples/curl-examples.sh   # override port
#   ./examples/curl-examples.sh 3                             # run only example 3
set -euo pipefail

HOST="${HOST:-http://localhost:8080}"
ONLY="${1:-}"

run() {
  local n="$1" name="$2" data="$3"
  if [ -n "$ONLY" ] && [ "$ONLY" != "$n" ]; then
    return
  fi
  echo "=== [$n] $name ==="
  curl -s "$HOST/v1/systemone" \
    -H 'Content-Type: application/json' \
    -d "$data" | python3 -m json.tool
  echo
}

# 1. Product review -> sentiment score + would-they-churn + one-line category
run 1 "product review triage" '{
  "state": {"message": "Battery life is way worse than advertised and it randomly shuts off. Second one Ive had to return. Not sure Ill buy this brand again."},
  "questions": {
    "sentiment": {
      "type": "score",
      "instructions": "How positive is this review?",
      "criteria": ["very negative", "negative", "neutral", "positive", "very positive"]
    },
    "category": {
      "type": "choice",
      "instructions": "What is this review mainly about?",
      "criteria": {"battery": "battery life or charging", "build_quality": "physical defects or durability", "software": "app or firmware issues", "price": "cost or value complaints"}
    },
    "at_risk_customer": {
      "type": "noul",
      "instructions": "Does this reviewer sound unlikely to purchase from this brand again?"
    }
  }
}'

# 2. Content moderation -> single noul question, minimal payload
run 2 "content moderation (single question)" '{
  "state": {"message": "Click here to claim your free prize now!!! Limited time, act fast, wire the processing fee to this account."},
  "questions": {
    "is_spam": {
      "type": "noul",
      "instructions": "Is this message spam or a scam?"
    }
  }
}'

# 3. HR triage -> combines all three question types on an internal message
run 3 "HR message triage" '{
  "state": {"message": "My manager has made three comments this month about my accent in front of the team. I feel humiliated and dont know who to talk to."},
  "questions": {
    "route": {
      "type": "choice",
      "instructions": "Which team should handle this?",
      "criteria": {"hr_conduct": "harassment, discrimination, or conduct concerns", "payroll": "pay or benefits issues", "it": "account or equipment issues", "facilities": "office or equipment issues"}
    },
    "severity": {
      "type": "score",
      "instructions": "How serious is this complaint?",
      "criteria": ["informational", "needs follow-up", "needs prompt attention", "needs immediate escalation"]
    },
    "confidential": {
      "type": "noul",
      "instructions": "Should this be handled confidentially, outside the normal ticket queue?"
    }
  }
}'

# 4. Non-English text -> exercises language auto-routing (or force with "model")
run 4 "non-English message (auto-routed)" '{
  "state": {"message": "Se me cobro dos veces por el mismo pedido y todavia no recibo el reembolso, llevo esperando dos semanas."},
  "questions": {
    "route": {
      "type": "choice",
      "instructions": "Where should this ticket go?",
      "criteria": {"billing": "payments, refunds, invoices", "bug": "the product is broken", "account": "login or access"}
    },
    "urgency": {
      "type": "score",
      "instructions": "How urgent is this message?",
      "criteria": ["routine, no rush", "today", "urgent", "critical, about to churn"]
    }
  }
}'

# 5. Same Spanish message, but pin the checkpoint explicitly instead of auto-routing
run 5 "non-English message (forced multilingual checkpoint)" '{
  "model": "multilingual",
  "state": {"message": "Se me cobro dos veces por el mismo pedido y todavia no recibo el reembolso, llevo esperando dos semanas."},
  "questions": {
    "urgency": {
      "type": "score",
      "instructions": "How urgent is this message?",
      "criteria": ["routine, no rush", "today", "urgent", "critical, about to churn"]
    }
  }
}'
