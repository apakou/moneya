---
name: voice-intent-parsing
description: Voice-first UX for MoneyA — speech-to-text provider selection for French/English plus African languages (Wolof, Bambara, Lingala, Pidgin), LLM function-calling schema for transfer intent extraction, confirmation-form prefill logic, swipe-to-confirm pattern, and fallback strategies. USE WHEN the user mentions voice, STT, speech, Whisper, Deepgram, transcription, LLM parsing, intent extraction, function calling, or swipe-to-confirm UX. DO NOT USE FOR general chatbot design unrelated to transfers.
---

# Voice Intent Parsing

## User flow

```
1. User taps/holds mic → records audio (max 15s)
2. Audio → STT (streaming preferred for perceived speed)
3. Transcript → LLM with function-calling → TransferIntent JSON
4. App prefills confirmation form from JSON
5. User edits by swiping fields (amount, recipient, source)
6. Swipe-to-confirm gesture → passcode / biometric
7. Backend executes
```

Voice is a **progressive enhancement** over the manual form. The form must always work standalone.

## STT provider comparison

| Provider | FR | EN | Wolof | Bambara | Lingala | Pidgin | Streaming | Price/min |
|---|---|---|---|---|---|---|---|---|
| **OpenAI Whisper API** | ★★★★ | ★★★★ | ⚠️ partial | ⚠️ partial | ⚠️ partial | ★★ | No (batch) | $0.006 |
| **Deepgram Nova-3** | ★★★★ | ★★★★★ | ❌ | ❌ | ❌ | ★★ | ✅ | $0.0043 |
| **Google Cloud STT** | ★★★★ | ★★★★ | ❌ | ❌ | ❌ | ⚠️ | ✅ | $0.016 |
| **AssemblyAI** | ★★★★ | ★★★★★ | ❌ | ❌ | ❌ | ★★ | ✅ | $0.0025 |
| **Flutter `speech_to_text`** (on-device) | ★★★ | ★★★ | ❌ | ❌ | ❌ | ❌ | ✅ | free |

**Recommendation**:
- **Primary**: Deepgram Nova-3 (streaming, cheap, great EN/FR).
- **Fallback for low-resource languages**: Whisper large-v3 self-hosted on GPU (has partial Wolof/Lingala training).
- **Offline fallback**: on-device `speech_to_text` when no network.

Record with the `record` package at 16kHz mono PCM. Upload via WebSocket for streaming providers.

## LLM intent extraction

Use a small, fast model (Gemini Flash, GPT-4o-mini, or Claude Haiku) with **strict JSON function calling**. Never rely on free-text parsing.

### Function schema

```json
{
  "name": "prepare_transfer",
  "description": "Extract a money transfer intent from user speech",
  "parameters": {
    "type": "object",
    "properties": {
      "amount_minor_units": {
        "type": "integer",
        "description": "Amount in smallest currency unit (e.g., 50000 for 500.00 XOF, since XOF has 0 decimals use the whole number)"
      },
      "currency": {
        "type": "string",
        "enum": ["XOF", "XAF", "NGN", "GHS", "KES"],
        "description": "Currency the user spoke in; infer from context if ambiguous"
      },
      "recipient_name": {
        "type": "string",
        "description": "Name or nickname spoken; used to match against contact list"
      },
      "recipient_phone": {
        "type": "string",
        "description": "Phone number if spoken, in any format"
      },
      "source": {
        "type": "string",
        "enum": ["moneya_balance", "wave", "orange_money", "mtn_momo", "moov", "airtel", "mpesa", "unspecified"]
      },
      "confidence": {
        "type": "number",
        "minimum": 0,
        "maximum": 1,
        "description": "Model's confidence that the utterance was a transfer request"
      },
      "missing_fields": {
        "type": "array",
        "items": {"type": "string", "enum": ["amount", "currency", "recipient", "source"]}
      }
    },
    "required": ["confidence", "missing_fields"]
  }
}
```

### System prompt essentials

```
You are MoneyA's transfer intent parser. The user speaks in French, English, or a
mix with local African language words. Extract a money transfer intent.

Rules:
- If the user says "cinq mille francs" → 5000 XOF (francs = XOF in UEMOA context).
- "naira" → NGN. "cedis" → GHS. "shillings" → KES. "francs CFA" → XOF or XAF
  based on sender country.
- "envoie à mon frère Modou" → recipient_name = "Modou" (don't include relation).
- If the user didn't specify source, set source = "unspecified".
- If confidence < 0.5, list ALL fields in missing_fields and don't guess.
- NEVER invent a phone number. Only fill recipient_phone if explicitly spoken.
- Round amounts exactly as spoken; don't re-denominate.
```

## Recipient disambiguation

After parsing, match `recipient_name` against the phone's contact list (via `flutter_contacts`):

1. Exact match (case/accent-insensitive) → auto-select.
2. Multiple matches → show picker with phone numbers.
3. No match → prompt user to pick from contacts or type number.
4. Name is missing but phone is present → skip matching, show phone.

**Never auto-pick from multiple matches** — misdirected money is the #1 catastrophic bug.

## Swipe-to-confirm UX

Form fields (top to bottom):
1. **Amount** — big number, tap to edit, horizontal swipe on digits to adjust by ±10%.
2. **Currency** — chip, tap to change.
3. **Recipient** — name + phone, tap to reselect from contacts.
4. **Source** — radio: MoneyA balance (default if funded) | Wave | Orange Money | …
5. **Fee + total** — read-only, recomputed on any edit (debounce 300ms).
6. **Swipe-to-confirm bar** at bottom — requires 80% horizontal swipe, haptic feedback, then biometric / passcode.

Accessibility: all swipe gestures must have a TalkBack/VoiceOver accessible button alternative.

## Fallback strategies

| Failure | Fallback |
|---|---|
| STT returns empty / low confidence | Show transcript + "Try again" + manual form |
| LLM returns `confidence < 0.5` | Open manual form prefilled with best-guess fields |
| LLM returns `missing_fields` non-empty | Open form focused on first missing field |
| Network offline | Offer manual form only; queue nothing |
| STT language not supported | Detect via short probe; route to Whisper fallback or prompt "Please speak in French or English" |

## Privacy

- Audio recordings are **not stored** after transcription completes.
- Transcripts are retained 24h for debugging, then purged — unless the user flags an error.
- Tell the user clearly in onboarding that voice is processed in the cloud.
- Provide a settings toggle "Voice input" default ON, with one-tap disable.
