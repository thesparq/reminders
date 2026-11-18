module [
	Result,
	MessageInput,
	MessageOutput,
	ReminderMilestone,
	ReminderRecord,
	InboxItem,
	EntityNote,
	WikiIndex,
	LlmConfig,
	AgentState,
	defaultState,
	defaultLlmConfig,
	encodeMessageInput,
	decodeMessageInput,
	encodeMessageOutput,
	decodeMessageOutput,
	encodeReminderMilestone,
	decodeReminderMilestone,
	encodeReminderRecord,
	decodeReminderRecord,
	encodeInboxItem,
	decodeInboxItem,
	encodeEntityNote,
	decodeEntityNote,
	encodeWikiIndex,
	decodeWikiIndex,
	encodeAgentState,
	decodeAgentState,
]

import pf.Json as GolemJson exposing [encode, decode]

Result(ok, err) : Try(ok, err)

MessageInput : {
	senderPhone : Str,
	text : Str,
	mediaType : Str,
	mediaId : Str,
}

MessageOutput : {
	status : Str,
	replyText : Str,
	reminderScheduled : Bool,
}

ReminderMilestone : {
	offsetMinutes : U64,
	triggerTimeMillis : U64,
}

ReminderRecord : {
	id : Str,
	title : Str,
	targetTimeMillis : U64,
	milestones : List(ReminderMilestone),
	currentStep : U64,
	status : Str,
}

InboxItem : {
	id : Str,
	path : Str,
	snippet : Str,
	timestamp : U64,
	status : Str,
}

EntityNote : {
	name : Str,
	category : Str,
	summary : Str,
	updatedAt : U64,
	relatedNotes : List(Str),
}

WikiIndex : {
	updatedAt : U64,
	inbox : List(InboxItem),
	reminders : List(ReminderRecord),
	entities : List(Str),
}

LlmConfig : {
	providerUrl : Str,
	model : Str,
	apiKey : Str,
}

defaultLlmConfig : LlmConfig
defaultLlmConfig = {
	providerUrl: "https://api.openai.com/v1/chat/completions",
	model: "gpt-4o-mini",
	apiKey: "",
}

AgentState : {
	ownerPhone : Str,
	telegramBotToken : Str,
	telegramChatId : Str,
	llmConfig : LlmConfig,
	activeReminders : List(ReminderRecord),
	inbox : List(InboxItem),
	entities : List(Str),
	totalProcessed : U64,
	lastProcessedTime : U64,
}

defaultState : Str -> AgentState
defaultState = |phone| {
	ownerPhone: phone,
	telegramBotToken: "",
	telegramChatId: "",
	llmConfig: defaultLlmConfig,
	activeReminders: [],
	inbox: [],
	entities: [],
	totalProcessed: 0.U64,
	lastProcessedTime: 0.U64,
}

# --- Codecs ---

encodeMessageInput : MessageInput -> Str
encodeMessageInput = |inp| encode(inp)

decodeMessageInput : Str -> Result(MessageInput, Str)
decodeMessageInput = |json| decode(json)

encodeMessageOutput : MessageOutput -> Str
encodeMessageOutput = |out| encode(out)

decodeMessageOutput : Str -> Result(MessageOutput, Str)
decodeMessageOutput = |json| decode(json)

encodeReminderMilestone : ReminderMilestone -> Str
encodeReminderMilestone = |m| encode(m)

decodeReminderMilestone : Str -> Result(ReminderMilestone, Str)
decodeReminderMilestone = |json| decode(json)

encodeReminderRecord : ReminderRecord -> Str
encodeReminderRecord = |r| encode(r)

decodeReminderRecord : Str -> Result(ReminderRecord, Str)
decodeReminderRecord = |json| decode(json)

encodeInboxItem : InboxItem -> Str
encodeInboxItem = |i| encode(i)

decodeInboxItem : Str -> Result(InboxItem, Str)
decodeInboxItem = |json| decode(json)

encodeEntityNote : EntityNote -> Str
encodeEntityNote = |e| encode(e)

decodeEntityNote : Str -> Result(EntityNote, Str)
decodeEntityNote = |json| decode(json)

encodeWikiIndex : WikiIndex -> Str
encodeWikiIndex = |idx| encode(idx)

decodeWikiIndex : Str -> Result(WikiIndex, Str)
decodeWikiIndex = |json| decode(json)

encodeAgentState : AgentState -> Str
encodeAgentState = |st| encode(st)

decodeAgentState : Str -> Result(AgentState, Str)
decodeAgentState = |json| decode(json)
