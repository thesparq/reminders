module [
	buildSendMessageRequest,
	buildSendMessagePayload,
	extractStringField,
	extractIdField,
	parseTelegramUpdate,
]

import pf.Json as GolemJson exposing [escape]
import pf.Types exposing [HttpRequest, Result]

buildSendMessagePayload : Str, Str -> Str
buildSendMessagePayload = |chatId, text|
	"{\"chat_id\":\"${escape(chatId)}\",\"text\":\"${escape(text)}\",\"parse_mode\":\"Markdown\"}"

buildSendMessageRequest : Str, Str, Str -> HttpRequest
buildSendMessageRequest = |botToken, chatId, text| {
	url: "https://api.telegram.org/bot${botToken}/sendMessage",
	method: "POST",
	headers: [{ name: "Content-Type", value: "application/json" }],
	body: buildSendMessagePayload(chatId, text),
	secretHeaders: [],
}

extractFieldVal : Str, Str -> Result(Str, Str)
extractFieldVal = |raw, key|
	match Str.split_first(raw, "\"${key}\":") {
		Ok({ after, .. }) => Ok(after)
		Err(_) =>
			match Str.split_first(raw, "\"${key}\" :") {
				Ok({ after, .. }) => Ok(after)
				Err(_) => Err("Field not found: ${key}")
			}
	}

extractStringField : Str, Str -> Str
extractStringField = |raw, key|
	match extractFieldVal(raw, key) {
		Ok(val) => {
			cleaned =
				if Str.starts_with(val, " \"") {
					Str.drop_prefix(val, " \"")
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

extractIdField : Str, Str -> Str
extractIdField = |raw, key|
	match extractFieldVal(raw, key) {
		Ok(val) => {
			cleaned = Str.trim_start(val)
			if Str.starts_with(cleaned, "\"") {
				extractStringField(raw, key)
			} else {
				digitsBytes = takeDigits(Str.to_utf8(cleaned), [])
				match Str.from_utf8(digitsBytes) {
					Ok(s) => s
					Err(_) => ""
				}
			}
		}
		Err(_) => ""
	}

## Parses inbound Telegram Webhook Update payload directly in pure Roc
parseTelegramUpdate : Str -> Result({ senderPhone : Str, chatId : Str, text : Str, mediaType : Str, mediaId : Str }, Str)
parseTelegramUpdate = |rawJson| {
	chatId =
		match Str.split_first(rawJson, "\"chat\":") {
			Ok({ after, .. }) => extractIdField(after, "id")
			Err(_) =>
				match Str.split_first(rawJson, "\"chat\" :") {
					Ok({ after, .. }) => extractIdField(after, "id")
					Err(_) => extractIdField(rawJson, "id")
				}
		}

	msgText = extractStringField(rawJson, "text")
	caption = extractStringField(rawJson, "caption")
	phone = extractStringField(rawJson, "phone_number")
	voiceFileId = extractStringField(rawJson, "file_id")

	isVoice = Str.contains(rawJson, "\"voice\":") or Str.contains(rawJson, "\"voice\" :")
	isPhoto = Str.contains(rawJson, "\"photo\":") or Str.contains(rawJson, "\"photo\" :")

	mediaType =
		if isVoice {
			"voice"
		} else if isPhoto {
			"image"
		} else {
			"text"
		}

	effectiveText =
		if !(Str.is_empty(msgText)) {
			msgText
		} else if !(Str.is_empty(caption)) {
			caption
		} else if isVoice {
			"[Voice Note Received]"
		} else if isPhoto {
			"[Photo Received]"
		} else {
			""
		}

	if Str.is_empty(chatId) and Str.is_empty(effectiveText) {
		Err("Invalid or empty Telegram update")
	} else {
		Ok({
			senderPhone: phone,
			chatId: chatId,
			text: effectiveText,
			mediaType: mediaType,
			mediaId: voiceFileId,
		})
	}
}
