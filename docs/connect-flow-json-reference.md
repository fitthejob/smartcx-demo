# Amazon Connect Contact Flow JSON — Reference, Issues & Lessons Learned

This document captures everything learned during the authoring and deployment of SmartCX Demo contact flows. It is intended as a reference for anyone maintaining or extending these flows, and as a record of the non-obvious schema requirements that caused deployment failures.

---

## 1. Correct JSON Schema

Amazon Connect contact flows use a proprietary JSON dialect called the Contact Flow Language (CFL). There are **two distinct variants** of this schema:

| Variant | Where it appears | Can be used with `CreateContactFlow` API? |
|---|---|---|
| **Console export format** | Downloaded via the Connect UI "Export" button | Partially — some block types are UI-only and rejected by the API |
| **API format** | Returned by `describe-contact-flow`, accepted by `create-contact-flow` | Yes |

Always treat the API format as authoritative. When in doubt, call `describe-contact-flow` on an existing flow and model your JSON against that output.

### 1.1 Top-Level Structure

```json
{
  "Version": "2019-10-30",
  "StartAction": "<uuid of first action>",
  "Metadata": {
    "entryPointPosition": { "x": 20, "y": 20 },
    "ActionMetadata": {
      "<action-uuid>": { "position": { "x": 20, "y": 20 } }
    },
    "Annotations": []
  },
  "Actions": [ ... ]
}
```

**Rules:**
- `StartAction` must match the `Identifier` of exactly one action in `Actions`.
- `Metadata.ActionMetadata` must contain a position entry for every action `Identifier` in the `Actions` array.
- `Metadata.Annotations` must be present as an explicit empty array `[]` — omitting it causes silent rejection on some instances.
- All `Metadata` keys are **lowerCamelCase** (`entryPointPosition`, not `EntryPointPosition`).
- Do not include `name`, `type`, `status`, or `hash` keys in `Metadata` when calling the create/update API. These are present in console exports but cause validation issues when submitted back.

### 1.2 Action Structure

Every action follows this shape:

```json
{
  "Identifier": "<uuid>",
  "Type": "<ActionType>",
  "Parameters": { ... },
  "Transitions": {
    "NextAction": "<uuid>",
    "Errors": [
      { "NextAction": "<uuid>", "ErrorType": "<type>" }
    ],
    "Conditions": [
      {
        "NextAction": "<uuid>",
        "Condition": { "Operator": "Equals", "Operands": ["<value>"] }
      }
    ]
  }
}
```

- `Identifier` must be a valid UUID (e.g. `a1b2c3d4-0001-0001-0001-000000000001`). Human-readable strings are rejected.
- `Transitions` is omitted entirely (not `{}`) only for terminal actions like `DisconnectParticipant` and `EndFlowExecution`.
- Every `Identifier` referenced in any `NextAction` field must exist as an action in the `Actions` array.

### 1.3 Valid Action Types (API-accepted)

| Action Type | Notes |
|---|---|
| `MessageParticipant` | Plays a TTS prompt. `Text` must be non-empty. |
| `GetParticipantInput` | Collects DTMF input. `Text` must be non-empty. Uses `StoreInput` and `InputTimeLimitSeconds`, not `Timeout`/`MaxDigits`. |
| `InvokeLambdaFunction` | Calls a Lambda. Only `NoMatchingError` is valid in `Errors`. Results are read via a subsequent `Compare` block using `$.External.<key>`. |
| `Compare` | Evaluates a contact attribute or external value. Use `$.External.<key>` for Lambda results. |
| `UpdateContactTargetQueue` | Sets the target queue. Must precede `TransferContactToQueue`. Takes `QueueId` as a full ARN. |
| `TransferContactToQueue` | Transfers to the previously set queue. `Parameters` must be `{}` — no `QueueId` here. |
| `UpdateContactAttributes` | Sets arbitrary contact attributes. |
| `DisconnectParticipant` | Terminates the contact. `Transitions` must be `{}`. |
| `EndFlowExecution` | Ends a whisper or module flow. `Transitions` must be `{}`. |

### 1.4 Queue Transfer Pattern

Queue transfer requires two actions in sequence — setting the target queue is separate from the transfer:

```json
{
  "Identifier": "<uuid-set-queue>",
  "Type": "UpdateContactTargetQueue",
  "Parameters": {
    "QueueId": "arn:aws:connect:<region>:<account>:instance/<id>/queue/<queue-id>"
  },
  "Transitions": { "NextAction": "<uuid-transfer>", "Errors": [...], "Conditions": [] }
},
{
  "Identifier": "<uuid-transfer>",
  "Type": "TransferContactToQueue",
  "Parameters": {},
  "Transitions": { "NextAction": "<uuid-disconnect>", "Errors": [...], "Conditions": [] }
}
```

### 1.5 Lambda Invocation + Result Check Pattern

Lambda results are **not** checked via inline `Conditions` on `InvokeLambdaFunction`. A separate `Compare` block reads `$.External.<key>`:

```json
{
  "Identifier": "<uuid-invoke>",
  "Type": "InvokeLambdaFunction",
  "Parameters": {
    "LambdaFunctionARN": "arn:aws:lambda:<region>:<account>:function:<name>",
    "InvocationTimeLimitSeconds": "8"
  },
  "Transitions": {
    "NextAction": "<uuid-compare>",
    "Errors": [{ "NextAction": "<uuid-fallback>", "ErrorType": "NoMatchingError" }],
    "Conditions": []
  }
},
{
  "Identifier": "<uuid-compare>",
  "Type": "Compare",
  "Parameters": { "ComparisonValue": "$.External.orderFound" },
  "Transitions": {
    "NextAction": "<uuid-not-found>",
    "Errors": [{ "NextAction": "<uuid-not-found>", "ErrorType": "NoMatchingCondition" }],
    "Conditions": [
      { "NextAction": "<uuid-found>", "Condition": { "Operator": "Equals", "Operands": ["true"] } }
    ]
  }
}
```

---

## 2. Known Issues

### 2.1 `InvalidContactFlowException` is a silent catch-all

The CLI and Terraform both surface this as a bare `400` with no detail. The actual `problems` array is in the HTTP response body but is suppressed by the AWS CLI output formatter.

**Workaround:** Use `--debug` on any `create-contact-flow` call and grep the output for `"problems"`:

```bash
aws connect create-contact-flow \
  --instance-id <id> \
  --name "DebugFlow" \
  --type CONTACT_FLOW \
  --content file://flow.json \
  --debug 2>&1 | grep -i problems
```

This exposes messages like:
```
{"problems":[{"message":"Invalid Action type. Type: SetLoggingBehavior, Path: Actions[0].Type"}]}
```

### 2.2 `SetLoggingBehavior` is not a valid API action type

This block type appears in console exports and is documented in some AWS guides, but **the `CreateContactFlow` API rejects it**. It is a UI-only construct.

Contact flow logging is enabled at the instance level, not in the flow JSON:

```bash
aws connect update-instance-attribute \
  --instance-id <id> \
  --attribute-type CONTACTFLOW_LOGS \
  --value true
```

Note: the attribute type is `CONTACTFLOW_LOGS` (no underscore between CONTACT and FLOW).

### 2.3 `SetRecordingAndAnalyticsBehavior` is also rejected by the API

Similarly rejected as an invalid action type by `CreateContactFlow`. Recording behavior is configured at the instance or queue level, not in flow JSON submitted via the API.

### 2.4 `TransferContactToQueue` does not accept a `QueueId` parameter

The console export format embeds the queue ARN directly in `TransferContactToQueue.Parameters.QueueId`. The API rejects this. The correct pattern is `UpdateContactTargetQueue` (with the ARN) followed by `TransferContactToQueue` (with empty `Parameters: {}`).

### 2.5 `GetParticipantInput` rejects an empty `Text` field

A `"Text": ""` parameter causes a `400`. Either provide prompt text or use a `PromptId` pointing to a silence audio file. In practice, providing a short fallback string such as `"Please make your selection."` is the simplest fix.

### 2.6 `InvokeLambdaFunction` does not support `TimeLimitExceeded` as an error type

Only `NoMatchingError` is accepted in the `Errors` array for this block type. A Lambda timeout is surfaced as `NoMatchingError` at runtime, so the fallback behavior is preserved.

### 2.7 `InvokeLambdaFunction` does not support inline `Conditions`

Attempting to branch directly on Lambda return values in the `Conditions` array of the invoke block is rejected. Use a subsequent `Compare` block reading `$.External.<key>` instead.

### 2.8 Console export JSON ≠ API-accepted JSON

The JSON exported from the Connect UI contains several block types and parameter shapes that are valid for re-import via the console but are rejected by the `CreateContactFlow` and `UpdateContactFlowContent` APIs. This is not documented clearly by AWS. Always validate against a known-good flow obtained via `describe-contact-flow`, not against a console export.

---

## 3. Challenges Overcome

### 3.1 No error detail from Terraform or the CLI

Terraform's AWS provider and the standard CLI both swallow the `problems` array from the HTTP response body, making it impossible to identify which block was rejected. The `--debug` flag on a direct CLI call was the only way to surface the actual validation message.

### 3.2 Incremental block isolation

Because the error gave no line number or action identifier, each block type had to be tested in isolation using minimal throwaway flows. The isolation sequence that proved reliable:

1. Minimal two-node flow (`MessageParticipant` → `DisconnectParticipant`) — establishes CLI is working
2. Add `GetParticipantInput` — discovered empty `Text` rejection
3. Add `UpdateContactTargetQueue` + `TransferContactToQueue` — passed
4. Add `InvokeLambdaFunction` + `Compare` — discovered `TimeLimitExceeded` rejection
5. Full flow — discovered `SetLoggingBehavior` rejection via `--debug`

### 3.3 Schema divergence between console and API

The initial flow JSON was modeled on console export syntax (human-readable identifiers, inline Lambda conditions, `SetLoggingBehavior`, `QueueId` on `TransferContactToQueue`). Every one of these assumptions required correction against the real API schema, which was discovered by exporting an existing flow via `describe-contact-flow`.

### 3.4 Lex v2 association not supported by the Terraform provider

`hashicorp/aws` v5.x `aws_connect_bot_association` only supports Lex v1 (name-based). Lex v2 requires an alias ARN, which the provider does not support. This was handled by associating the bot directly in the Connect console (Channels → Amazon Lex) and documenting the gap. The `lex_bot_alias_arn` output is passed through for reference in `deploy.sh`.

---

## 4. Lessons Learned

1. **Use `--debug` immediately on any `InvalidContactFlowException`.** Do not iterate blind. The problems array in the response body is the only reliable source of truth.

2. **Never model flow JSON from console exports alone.** Always cross-reference against `describe-contact-flow` output from a working flow. The console export schema and the API schema are not the same.

3. **Isolate blocks incrementally.** When a full flow fails, reduce to the smallest possible failing case. The Connect validator rejects on the first problem it finds, so a single bad block can mask all others.

4. **Instance-level features belong outside the flow.** Logging (`CONTACTFLOW_LOGS`), recording, and analytics are instance or queue configuration — not flow blocks. Putting them in flow JSON is a common mistake driven by console export artifacts.

5. **`TransferContactToQueue` is always a two-step operation via the API.** Set the queue with `UpdateContactTargetQueue`, then transfer with `TransferContactToQueue` and empty parameters. The single-step pattern seen in console exports does not work via the API.

6. **Lambda results require a `Compare` block.** `InvokeLambdaFunction` only routes on success/error, not on return values. All branching on Lambda output must go through a `Compare` block reading `$.External.<key>`.

7. **All action identifiers must be real UUIDs.** Human-readable strings such as `"entry"` or `"set-queue-support"` are rejected. Generate UUIDs with `node -e "const {randomUUID}=require('crypto'); console.log(randomUUID())"`.

8. **Every action must be reachable from `StartAction`.** Unreferenced actions cause the entire flow to be rejected. Verify the graph is fully connected before submitting.
