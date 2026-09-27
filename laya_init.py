import laya

# Load a specific checkpoint directly from the hub
agent = laya.load("convaiinnovations/laya")  # English root

state = {"message": "I was charged twice for invoice 4411. Please refund me today."}
questions = {
    "department": {
        "type": "choice",
        "instructions": "Where should this ticket go?",
        "criteria": {
            "billing": "payments, refunds, invoices",
            "bug": "the product is broken",
            "account": "login or access",
        },
    },
    "urgency": {
        "type": "score",
        "instructions": "How urgent is this message?",
        "criteria": ["routine, no rush", "today", "urgent", "critical, about to churn"],
    },
    "churn_risk": {
        "type": "noul",
        "instructions": "Is this customer at risk of churning?",
    },
}

# Run all questions in ONE single forward pass (~35 ms on GPU)
result = agent.predict(state, questions)
answers = result["answers"]

print("Department :", answers["department"]["choice"])
print("Urgency    :", answers["urgency"]["score"])
print("Churn Risk :", answers["churn_risk"]["noul"])
