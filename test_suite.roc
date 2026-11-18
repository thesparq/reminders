app [agent] { pf: platform "https://github.com/thesparq/roc-golem/releases/download/v1.4.2/sCMpPilBt65rdAVsPINB5xqG7FtlRnTGj6Vj61B6ulE.tar.zst" }

import pf.Types exposing [Result]
import pf.Golem exposing [Agent]
import RemindersAgent
import Types exposing [
	AgentState,
	MessageInput,
	MessageOutput,
	ReminderRecord,
	ReminderMilestone,
	InboxItem,
	encodeMessageInput,
	decodeMessageInput,
	encodeMessageOutput,
	decodeMessageOutput,
	encodeReminderRecord,
	decodeReminderRecord,
]
import Scheduler exposing [calculateLadder, formatMilestoneNotice, parseReminderIntent]
import Wiki exposing [formatInboxNote, formatEntityNote, formatAgendaMarkdown, isAgendaQuery]

State : AgentState

agent : Agent(State)
agent = RemindersAgent.agent

# --- Unit Test 1: Codec Roundtrip ---

testInput : MessageInput
testInput = {
	senderPhone: "+1234567890",
	text: "Remind me to call Mom",
	mediaType: "text",
	mediaId: "",
}

encodedInp = encodeMessageInput(testInput)
decodedInpRes = decodeMessageInput(encodedInp)

expect
	match decodedInpRes {
		Ok(decoded) => decoded.senderPhone == "+1234567890" and decoded.text == "Remind me to call Mom"
		Err(_) => False
	}

# --- Unit Test 2: Exponential Reminder Ladder (Full 35-min event) ---

nowMs = 1000000.U64
target35m = nowMs + (35.U64 * 60000.U64)

fullLadder = calculateLadder(target35m, nowMs)

# Must contain all 7 countdown milestones: 30m, 20m, 10m, 5m, 2m, 1m, 0m
expect List.len(fullLadder) == 7

# Verify first milestone is 30 minutes
expect
	match fullLadder {
		[first, ..] => first.offsetMinutes == 30.U64
		_ => False
	}

# --- Unit Test 3: Truncated Ladder for Near-Term Events (12-min event) ---

target12m = nowMs + (12.U64 * 60000.U64)
truncatedLadder = calculateLadder(target12m, nowMs)

# Offsets > 12m (30m, 20m) must be excluded. Active: [10m, 5m, 2m, 1m, 0m] -> 5 milestones
expect List.len(truncatedLadder) == 5

expect
	match truncatedLadder {
		[first, ..] => first.offsetMinutes == 10.U64
		_ => False
	}

# --- Unit Test 4: Milestone Notice Formats ---

expect formatMilestoneNotice("Dentist", 0.U64) == "⏰ *REMINDER:* Dentist\nIt is time right now!"
expect formatMilestoneNotice("Dentist", 1.U64) == "🔔 *Final Notice:* Dentist begins in 1 minute!"
expect formatMilestoneNotice("Dentist", 10.U64) == "🔔 *Upcoming Reminder:* Dentist in 10 minutes."

# --- Unit Test 5: Agenda Query Detection ---

expect isAgendaQuery("/agenda") == True
expect isAgendaQuery("agenda") == True
expect isAgendaQuery("what is my agenda today?") == True
expect isAgendaQuery("What's my agenda?") == True
expect isAgendaQuery("Remember to buy milk") == False

# --- Unit Test 6: Wiki Formatting ---

inboxNote = formatInboxNote("note_1", 1000000.U64, "Buy groceries")
expect Str.starts_with(inboxNote, "---\nid: note_1")

# --- Unit Test 7: LLM Request & Response Parsing ---

import Llm exposing [buildChatCompletionRequest, parseChatCompletionResponse]
import Types exposing [defaultLlmConfig]

testLlmConfig = {
	providerUrl: "https://api.openai.com/v1/chat/completions",
	model: "gpt-4o-mini",
	apiKey: "test-api-key",
}

llmReq = buildChatCompletionRequest(testLlmConfig, "Remind me to call Mom tomorrow at 5pm", 1700000000000.U64)
expect llmReq.method == "POST"
expect llmReq.url == "https://api.openai.com/v1/chat/completions"

mockResp = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"isReminder\\\": true, \\\"title\\\": \\\"Call Mom\\\", \\\"targetMillis\\\": 1700086400000, \\\"reply\\\": \\\"Scheduled a reminder to call Mom.\\\"}\"}}]}"
parsedRes = parseChatCompletionResponse(mockResp)
expect
	match parsedRes {
		Ok(parsed) =>
			parsed.isReminder == True and
			parsed.title == "Call Mom" and
			parsed.targetMillis == 1700086400000.U64
		Err(_) => False
	}

# --- Unit Test 8: Pure Roc Telegram Webhook Update Parsing ---

import Telegram exposing [parseTelegramUpdate, buildSendMessageRequest]

mockTelegramUpdate = "{\"update_id\":12345,\"message\":{\"chat\":{\"id\":998877},\"text\":\"Remind me to buy groceries tomorrow at 5pm\",\"contact\":{\"phone_number\":\"+1234567890\"}}}"
parsedTgUpdate = parseTelegramUpdate(mockTelegramUpdate)

expect
	match parsedTgUpdate {
		Ok(u) =>
			u.chatId == "998877" and
			u.text == "Remind me to buy groceries tomorrow at 5pm" and
			u.senderPhone == "+1234567890" and
			u.mediaType == "text"
		Err(_) => False
	}

tgReq = buildSendMessageRequest("123456:ABC-DEF", "998877", "Hello from Roc Golem!")
expect tgReq.method == "POST"
expect Str.contains(tgReq.url, "api.telegram.org")
expect Str.contains(tgReq.body, "998877")

