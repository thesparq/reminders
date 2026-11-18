module [
	formatInboxNote,
	formatEntityNote,
	formatAgendaMarkdown,
	buildIndexJson,
	isAgendaQuery,
]

import Types exposing [InboxItem, ReminderRecord, EntityNote, WikiIndex, encodeWikiIndex]

formatInboxNote : Str, U64, Str -> Str
formatInboxNote = |id, timestamp, content|
	"---\nid: ${id}\ntimestamp: ${Str.inspect(timestamp)}\nstatus: pending\n---\n\n# Inbox Note\n\n${content}\n"

formatEntityNote : Str, Str, Str, U64, List(Str) -> Str
formatEntityNote = |name, category, summary, updatedAt, relatedNotes| {
	relLinks =
		if List.is_empty(relatedNotes) {
			"_None_"
		} else {
			relatedNotes
				|> List.map(|r| "[[${r}]]")
				|> Str.join_with(", ")
		}

	header = "---\nentity: ${name}\ncategory: ${category}\nupdatedAt: ${Str.inspect(updatedAt)}\n---\n\n"
	body = "# ${name} (${category})\n\n${summary}\n\n## Related Entities\n${relLinks}\n"
	"${header}${body}"
}

formatAgendaMarkdown : List(ReminderRecord), List(InboxItem) -> Str
formatAgendaMarkdown = |reminders, inboxItems| {
	remHeader = "# Daily Agenda & Active Reminders\n\n## 🔔 Scheduled Reminders\n"
	remLines =
		if List.is_empty(reminders) {
			"_No reminders currently scheduled._\n"
		} else {
			reminders
				|> List.map(
					|r|
						"- **${r.title}** (Target: ${Str.inspect(r.targetTimeMillis)}) [Status: ${r.status}]\n",
				)
				|> Str.join_with("")
		}

	inboxHeader = "\n## 📥 Pending Inbox Notes\n"
	inboxLines =
		if List.is_empty(inboxItems) {
			"_Inbox is clean. All notes organized in LLM Wiki._\n"
		} else {
			inboxItems
				|> List.map(|item| "- ${item.snippet} (`${item.path}`)\n")
				|> Str.join_with("")
		}

	"${remHeader}${remLines}${inboxHeader}${inboxLines}"
}

buildIndexJson : List(InboxItem), List(ReminderRecord), List(Str), U64 -> Str
buildIndexJson = |inboxItems, reminders, entities, updatedAt|
	encodeWikiIndex({
		updatedAt: updatedAt,
		inbox: inboxItems,
		reminders: reminders,
		entities: entities,
	})

isAgendaQuery : Str -> Bool
isAgendaQuery = |rawText| {
	trimmed = Str.trim(rawText)
	trimmed == "/agenda"
	or trimmed == "agenda"
	or Str.starts_with(trimmed, "what is my agenda")
	or Str.starts_with(trimmed, "What is my agenda")
	or Str.starts_with(trimmed, "what's my agenda")
	or Str.starts_with(trimmed, "What's my agenda")
	or Str.starts_with(trimmed, "show agenda")
}
