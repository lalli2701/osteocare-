from __future__ import annotations

import hashlib


knowledge = [
    "Osteoporosis is a disease where bones become weak and brittle.",
    "It is often called a silent disease because there are usually no symptoms before a fracture.",
    "Bone mineral density naturally decreases with age.",
    "Women after menopause have higher osteoporosis risk due to lower estrogen levels.",
    "Smoking reduces bone density over time.",
    "Excess alcohol intake can negatively affect bone formation and increase fracture risk.",
    "Calcium is essential for strong bones.",
    "Vitamin D helps the body absorb calcium effectively.",
    "Weight-bearing exercise helps strengthen bones.",
    "Difficulty walking and poor balance can increase fall and fracture risk.",
    "Family history of osteoporosis can increase personal risk.",
    "Low body weight is associated with lower bone density.",
    "Long-term use of corticosteroids can weaken bones.",
    "Previous fractures after minor trauma suggest increased fracture risk.",
    "Regular walking can support bone and muscle health.",
    "Strength training improves bone and muscle strength.",
    "Balance exercises may reduce fall risk in older adults.",
    "Calcium-rich foods include milk, curd, paneer, yogurt, and cheese.",
    "Leafy green vegetables contribute useful minerals for bone health.",
    "Fortified foods can be a practical source of vitamin D.",
    "Sunlight exposure supports vitamin D production in the skin.",
    "People with limited sunlight exposure may need vitamin D evaluation.",
    "High salt intake may increase calcium loss in urine.",
    "Very sedentary lifestyle is a risk factor for weaker bones.",
    "Physical activity during adolescence helps build higher peak bone mass.",
    "Peak bone mass is usually reached in early adulthood.",
    "Falls are a major cause of fractures in older adults.",
    "Home safety changes can reduce fall risk.",
    "Examples of home safety include removing loose rugs and improving lighting.",
    "Using proper footwear can reduce slipping risk.",
    "Hip and spine are common sites of osteoporotic fractures.",
    "Vertebral fractures can occur with minimal trauma.",
    "Height loss in older age can be associated with vertebral compression fractures.",
    "Back pain in older adults can sometimes be related to vertebral fractures.",
    "Dual-energy X-ray absorptiometry, or DXA, is commonly used to measure bone density.",
    "A T-score at or below -2.5 is generally used as a diagnostic threshold for osteoporosis.",
    "Osteopenia indicates low bone density but not severe enough for osteoporosis diagnosis.",
    "People with osteopenia can still have elevated fracture risk depending on other factors.",
    "Nutrition, exercise, and medical guidance are all important for prevention.",
    "Adequate protein intake supports muscle and bone health.",
    "Muscle strength supports stability and can reduce falls.",
    "Chronic conditions such as thyroid disorders can influence bone metabolism.",
    "Some cancer treatments can accelerate bone loss.",
    "Smoking cessation can improve long-term bone outcomes.",
    "Limiting alcohol can support better bone health.",
    "Regular reassessment helps track bone health risk over time.",
    "Medication decisions should always be made with a qualified clinician.",
    "This assistant is educational and does not replace medical diagnosis.",
    "People with fragility fractures should seek clinical evaluation for osteoporosis.",
    "Early prevention is important because bone loss accumulates gradually.",
    "Daily habits such as activity, diet, and fall prevention strongly influence bone health."
]


def get_knowledge_version() -> str:
    payload = "\n".join(knowledge).encode("utf-8", errors="ignore")
    return hashlib.sha1(payload).hexdigest()[:12]


KNOWLEDGE_VERSION = get_knowledge_version()
