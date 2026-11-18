module [
	LlmParsedIntent,
	buildChatCompletionRequest,
	buildChatCompletionJson,
	parseChatCompletionResponse,
]

import pf.Json as GolemJson exposing [escape]
import pf.Types as PfTypes exposing [HttpRequest]
import pf.Parse exposing [parseU64Or]
import Types exposing [Result, LlmConfig]

LlmParsedIntent : {
	isReminder : Bool,
	title : Str,
	targetMillis : U64,
	reply : Str,
	extractedEntities : List(Str),
}

extractFieldVal : Str, Str -> Result(Str, Str)
extractFieldVal = |raw, key|
	match Str.split_first(raw, key) {
		Ok({ after: afterKey, .. }) =>
			match Str.split_first(afterKey, ":") {
				Ok({ after: afterColon, .. }) =>
					Ok(Str.trim_start(afterColon))
				Err(_) => Err("Missing colon after key")
			}
		Err(_) => Err("Key not found")
	}

extractJsonBoolField : Str, Str -> Bool
extractJsonBoolField = |raw, key|
	match extractFieldVal(raw, key) {
		Ok(val) => Str.starts_with(val, "true")
		Err(_) => False
	}

extractJsonStringField : Str, Str -> Str
extractJsonStringField = |raw, key|
	match extractFieldVal(raw, key) {
		Ok(val) => {
			cleaned =
				if Str.starts_with(val, "\\\"") {
					Str.drop_prefix(val, "\\\"")
				} else if Str.starts_with(val, "\"") {
					Str.drop_prefix(val, "\"")
				} else {
					val
				}
			match Str.split_first(cleaned, "\"") {
				Ok({ before, .. }) =>
					if Str.ends_with(before, "\\") {
						Str.drop_suffix(before, "\\")
					} else {
						before
					}
				Err(_) => cleaned
			}
		}
		Err(_) => ""
	}

takeDigits : List(U8), List(U8) -> List(U8)
takeDigits = |bytes, acc|
	match bytes {
		[] => acc
		[first, .. as rest] =>
			if first >= 48 and first <= 57 {
				takeDigits(rest, List.append(acc, first))
			} else {
				acc
			}
	}

extractJsonU64Field : Str, Str -> U64
extractJsonU64Field = |raw, key|
	match extractFieldVal(raw, key) {
		Ok(val) => {
			digitsBytes = takeDigits(Str.to_utf8(val), [])
			match Str.from_utf8(digitsBytes) {
				Ok(s) => parseU64Or(s, 0.U64)
				Err(_) => 0.U64
			}
		}
		Err(_) => 0.U64
	}

## Constructs standard Chat Completions JSON request
buildChatCompletionRequest : LlmConfig, Str, U64 -> HttpRequest
buildChatCompletionRequest = |config, userMessage, nowMillis| {
	systemPrompt =
		"You are a personal reminder assistant and LLM Wiki organizer. Given a message and current timestamp in epoch milliseconds (${Str.inspect(nowMillis)}), output JSON: {\\\"isReminder\\\": boolean, \\\"title\\\": string, \\\"targetMillis\\\": number, \\\"reply\\\": string, \\\"extractedEntities\\\": [string]}. If not a reminder, set isReminder to false and targetMillis to 0."

	body =
		"{\"model\":\"${config.model}\",\"response_format\":{\"type\":\"json_object\"},\"messages\":[{\"role\":\"system\",\"content\":\"${escape(systemPrompt)}\"},{\"role\":\"user\",\"content\":\"${escape(userMessage)}\"}]}"

	{
		url: config.providerUrl,
		method: "POST",
		headers: [
			{ name: "Content-Type", value: "application/json" },
			{ name: "Authorization", value: "Bearer ${config.apiKey}" },
		],
		body: body,
		secretHeaders: [],
	}
}

## Constructs raw JSON HTTP request string matching host Value::as_object expectation
buildChatCompletionJson : LlmConfig, Str, U64 -> Str
buildChatCompletionJson = |config, userMessage, nowMillis| {
	systemPrompt =
		"You are a personal reminder assistant and LLM Wiki organizer. Given a message and current timestamp in epoch milliseconds (${Str.inspect(nowMillis)}), output JSON: {\\\"isReminder\\\": boolean, \\\"title\\\": string, \\\"targetMillis\\\": number, \\\"reply\\\": string, \\\"extractedEntities\\\": [string]}. If not a reminder, set isReminder to false and targetMillis to 0."

	body =
		"{\"model\":\"${config.model}\",\"response_format\":{\"type\":\"json_object\"},\"messages\":[{\"role\":\"system\",\"content\":\"${escape(systemPrompt)}\"},{\"role\":\"user\",\"content\":\"${escape(userMessage)}\"}]}"

	"{\"url\":\"${escape(config.providerUrl)}\",\"method\":\"POST\",\"headers\":{\"Content-Type\":\"application/json\",\"Authorization\":\"Bearer ${escape(config.apiKey)}\"},\"body\":\"${escape(body)}\"}"
}

## Parses the model completion content from Chat Completion response
parseChatCompletionResponse : Str -> Result(LlmParsedIntent, Str)
parseChatCompletionResponse = |respBody| {
	match Str.split_first(respBody, "content") {
		Ok({ after, .. }) => {
			trimmed = Str.trim_start(after)
			isReminder = extractJsonBoolField(trimmed, "isReminder")
			title = extractJsonStringField(trimmed, "title")
			targetMillis = extractJsonU64Field(trimmed, "targetMillis")
			reply = extractJsonStringField(trimmed, "reply")
			Ok({
				isReminder: isReminder,
				title: if Str.is_empty(title) { "Extracted Reminder" } else { title },
				targetMillis: targetMillis,
				reply: if Str.is_empty(reply) { "Processed message." } else { reply },
				extractedEntities: [],
			})
		}
		Err(_) =>
			Err("Failed to parse LLM completion response: missing content field")
	}
}
