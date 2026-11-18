module [
	agent,
	processMessageMethod,
	triggerReminderMethod,
	midnightOrganizerMethod,
	queryAgendaMethod,
]

import pf.Golem exposing [
	Agent,
	Method,
	define,
	registerEffectfulTyped,
	registerReadOnlyTyped,
	withHttpMount,
	method,
	build,
	now,
	workerId,
	rpcSchedule,
	writeFile,
	httpRequest,
	http,
]
import pf.Effect
import Types exposing [
	Result,
	AgentState,
	MessageInput,
	MessageOutput,
	ReminderRecord,
	ReminderMilestone,
	InboxItem,
	defaultState,
	decodeMessageInput,
	encodeMessageOutput,
	decodeAgentState,
	encodeAgentState,
]
import Scheduler exposing [calculateLadder, formatMilestoneNotice, parseReminderIntent]
import Wiki exposing [formatInboxNote, formatAgendaMarkdown, buildIndexJson, isAgendaQuery]
import Telegram exposing [buildSendMessageRequest, parseTelegramUpdate]
import Llm exposing [buildChatCompletionRequest, buildChatCompletionJson, parseChatCompletionResponse]

processMessageMethod : Method(MessageInput, MessageOutput)
processMessageMethod = method({
	name: "process_message",
	description: "Processes inbound user message, updates LLM wiki, and schedules reminders if applicable.",
	promptHint: "Call to process an incoming text/audio/image message from the user.",
})

triggerReminderMethod : Method(Str, Str)
triggerReminderMethod = method({
	name: "trigger_reminder",
	description: "Fires scheduled reminder milestone and schedules subsequent countdown steps.",
	promptHint: "Internal callback invoked by durable timer to trigger a reminder milestone.",
})

midnightOrganizerMethod : Method(Str, Str)
midnightOrganizerMethod = method({
	name: "midnight_organizer",
	description: "Executes periodic midnight organization of unacted inbox notes into the wiki.",
	promptHint: "Internal callback invoked at midnight to organize notes and refresh agenda.",
})

queryAgendaMethod : Method(Str, Str)
queryAgendaMethod = method({
	name: "query_agenda",
	description: "Returns the user's current daily agenda and active reminders.",
	promptHint: "Call to query current agenda and scheduled events.",
})

findReminderById : List(ReminderRecord), Str -> Result(ReminderRecord, Str)
findReminderById = |list, targetId|
	match list {
		[] => Err("Reminder not found")
		[first, .. as rest] =>
			if first.id == targetId {
				Ok(first)
			} else {
				findReminderById(rest, targetId)
			}
	}

getMilestoneAtStep : List(ReminderMilestone), U64 -> Result(ReminderMilestone, Str)
getMilestoneAtStep = |list, targetIndex|
	match list {
		[] => Err("Milestone index out of bounds")
		[first, .. as rest] =>
			if targetIndex == 0.U64 {
				Ok(first)
			} else {
				getMilestoneAtStep(rest, targetIndex - 1.U64)
			}
	}

initAgent : Str -> Result(AgentState, Str)
initAgent = |configJson|
	match decodeAgentState(configJson) {
		Ok(st) => Ok(st)
		Err(_) => Ok(defaultState(""))
	}

serializeState : AgentState -> Str
serializeState = |state|
	encodeAgentState(state)

deserializeState : Str -> Result(AgentState, Str)
deserializeState = |raw|
	match decodeAgentState(raw) {
		Ok(st) => Ok(st)
		Err(_) => Ok(defaultState(""))
	}

resolveMessageIntent : AgentState, Str, U64 -> Effect.Effect({ isReminder : Bool, title : Str, targetMillis : U64, reply : Str })
resolveMessageIntent = |state, messageText, nowMillis|
	if !(Str.is_empty(state.llmConfig.apiKey)) {
		llmJson = buildChatCompletionJson(state.llmConfig, messageText, nowMillis)
		Effect.and_then(
			http(llmJson),
			|httpRes| {
				parsed =
					match httpRes {
						Ok(respJson) =>
							match parseChatCompletionResponse(respJson) {
								Ok(res) =>
									if res.isReminder and res.targetMillis > nowMillis {
										{
											isReminder: res.isReminder,
											title: res.title,
											targetMillis: res.targetMillis,
											reply: res.reply,
										}
									} else {
										match parseReminderIntent(messageText, nowMillis) {
											Ok(p) => {
												isReminder: p.isReminder,
												title: p.title,
												targetMillis: p.targetMillis,
												reply: res.reply,
											}
											Err(_) => {
												isReminder: res.isReminder,
												title: res.title,
												targetMillis: res.targetMillis,
												reply: res.reply,
											}
										}
									}
								Err(_) =>
									match parseReminderIntent(messageText, nowMillis) {
										Ok(p) => {
											isReminder: p.isReminder,
											title: p.title,
											targetMillis: p.targetMillis,
											reply: "",
										}
										Err(_) => {
											isReminder: False,
											title: messageText,
											targetMillis: 0.U64,
											reply: "",
										}
									}
							}
						Err(_) =>
							match parseReminderIntent(messageText, nowMillis) {
								Ok(p) => {
									isReminder: p.isReminder,
									title: p.title,
									targetMillis: p.targetMillis,
									reply: "",
								}
								Err(_) => {
									isReminder: False,
									title: messageText,
									targetMillis: 0.U64,
									reply: "",
								}
							}
					}
				Effect.always(parsed)
			},
		)
	} else {
		localParsed =
			match parseReminderIntent(messageText, nowMillis) {
				Ok(p) => {
					isReminder: p.isReminder,
					title: p.title,
					targetMillis: p.targetMillis,
					reply: "",
				}
				Err(_) => {
					isReminder: False,
					title: messageText,
					targetMillis: 0.U64,
					reply: "",
				}
			}
		Effect.always(localParsed)
	}

dispatchTelegramAlert : AgentState, Str -> Effect.Effect(Result(Str, Str))
dispatchTelegramAlert = |state, text|
	if !(Str.is_empty(state.telegramBotToken)) and !(Str.is_empty(state.telegramChatId)) {
		req = buildSendMessageRequest(state.telegramBotToken, state.telegramChatId, text)
		httpRequest(req)
	} else {
		Effect.always(Ok("Telegram notification skipped (bot token or chat ID not set)"))
	}

handleProcessMessage : AgentState, MessageInput -> Effect.Effect(Result({ state : AgentState, out : MessageOutput }, Str))
handleProcessMessage = |state, rawInput| {
	isTgUpdate = Str.contains(rawInput.text, "\"update_id\"")

	input =
		if isTgUpdate {
			match parseTelegramUpdate(rawInput.text) {
				Ok(tg) => {
					senderPhone: if Str.is_empty(tg.senderPhone) { rawInput.senderPhone } else { tg.senderPhone },
					text: tg.text,
					mediaType: tg.mediaType,
					mediaId: tg.mediaId,
				}
				Err(_) => rawInput
			}
		} else {
			rawInput
		}

	extractedChatId =
		if isTgUpdate {
			match parseTelegramUpdate(rawInput.text) {
				Ok(tg) => tg.chatId
				Err(_) => state.telegramChatId
			}
		} else {
			state.telegramChatId
		}

	effectiveState =
		if !(Str.is_empty(extractedChatId)) {
			{ ..state, telegramChatId: extractedChatId }
		} else {
			state
		}

	if !(Str.is_empty(effectiveState.ownerPhone)) and input.senderPhone != effectiveState.ownerPhone {
		Effect.always(
			Ok({
				state: effectiveState,
				out: {
					status: "rejected",
					replyText: "Unauthorized sender. This assistant is private to its owner.",
					reminderScheduled: False,
				},
			}),
		)
	} else if isAgendaQuery(input.text) {
		agendaText = formatAgendaMarkdown(effectiveState.activeReminders, effectiveState.inbox)
		Effect.and_then(
			dispatchTelegramAlert(effectiveState, agendaText),
			|_|
				Effect.always(
					Ok({
						state: effectiveState,
						out: {
							status: "success",
							replyText: agendaText,
							reminderScheduled: False,
						},
					}),
				),
		)
	} else {
		Effect.and_then(
			now,
			|nowMillis| {
				Effect.and_then(
					resolveMessageIntent(effectiveState, input.text, nowMillis),
					|intent| {
						noteId = "note_${Str.inspect(nowMillis)}"
						notePath = "wiki_inbox_${noteId}.md"
						noteContent = formatInboxNote(noteId, nowMillis, input.text)

						inboxEntry : InboxItem
						inboxEntry = {
							id: noteId,
							path: notePath,
							snippet: input.text,
							timestamp: nowMillis,
							status: "pending",
						}

						nextInbox = List.append(effectiveState.inbox, inboxEntry)

						if intent.isReminder {
					ladder = calculateLadder(intent.targetMillis, nowMillis)
					remId = "rem_${Str.inspect(nowMillis)}"
					newReminder : ReminderRecord
					newReminder = {
						id: remId,
						title: intent.title,
						targetTimeMillis: intent.targetMillis,
						milestones: ladder,
						currentStep: 0.U64,
						status: "active",
					}

					nextReminders = List.append(state.activeReminders, newReminder)
					nextIndexJson = buildIndexJson(nextInbox, nextReminders, state.entities, nowMillis)
					agendaMd = formatAgendaMarkdown(nextReminders, nextInbox)

					match ladder {
						[] => {
							Effect.and_then(
								writeFile(notePath, noteContent),
								|_|
									Effect.and_then(
										writeFile("wiki_index.json", nextIndexJson),
										|_|
											Effect.and_then(
												writeFile("wiki_agenda.md", agendaMd),
												|_| {
													nextState = {
														..effectiveState,
														inbox: nextInbox,
														activeReminders: nextReminders,
														totalProcessed: effectiveState.totalProcessed + 1.U64,
														lastProcessedTime: nowMillis,
													}
													reply = "Recorded reminder '${intent.title}' for immediate action."
													Effect.and_then(
														dispatchTelegramAlert(nextState, reply),
														|_|
															Effect.always(
																Ok({
																	state: nextState,
																	out: {
																		status: "success",
																		replyText: reply,
																		reminderScheduled: True,
																	},
																}),
															),
													)
												},
											),
									),
							)
						}
						[firstMilestone, ..] => {
							delayMillis =
								if firstMilestone.triggerTimeMillis > nowMillis {
									firstMilestone.triggerTimeMillis - nowMillis
								} else {
									1000.U64
								}

							Effect.and_then(
								workerId,
								|selfId|
									Effect.and_then(
										rpcSchedule(selfId, triggerReminderMethod, remId, delayMillis),
										|_schedRes|
											Effect.and_then(
												writeFile(notePath, noteContent),
												|_|
													Effect.and_then(
														writeFile("wiki_index.json", nextIndexJson),
														|_|
															Effect.and_then(
																writeFile("wiki_agenda.md", agendaMd),
																|_| {
																	nextState = {
																		..effectiveState,
																		inbox: nextInbox,
																		activeReminders: nextReminders,
																		totalProcessed: effectiveState.totalProcessed + 1.U64,
																		lastProcessedTime: nowMillis,
																	}
																	ladderCount = List.len(ladder)
																	reply = "🔔 Scheduled reminder '${intent.title}' with ${Str.inspect(ladderCount)} exponential countdown warnings."
																	Effect.and_then(
																		dispatchTelegramAlert(nextState, reply),
																		|_|
																			Effect.always(
																				Ok({
																					state: nextState,
																					out: {
																						status: "success",
																						replyText: reply,
																						reminderScheduled: True,
																					},
																				}),
																			),
																	)
																},
															),
													),
											),
									),
							)
						}
					}
				} else {
					nextIndexJson = buildIndexJson(nextInbox, effectiveState.activeReminders, effectiveState.entities, nowMillis)
					agendaMd = formatAgendaMarkdown(effectiveState.activeReminders, nextInbox)

					Effect.and_then(
						writeFile(notePath, noteContent),
						|_|
							Effect.and_then(
								writeFile("wiki_index.json", nextIndexJson),
								|_|
									Effect.and_then(
										writeFile("wiki_agenda.md", agendaMd),
										|_| {
											nextState = {
												..effectiveState,
												inbox: nextInbox,
												totalProcessed: effectiveState.totalProcessed + 1.U64,
												lastProcessedTime: nowMillis,
											}
											reply = "Captured to your LLM Wiki (`${noteId}`)."
											Effect.and_then(
												dispatchTelegramAlert(nextState, reply),
												|_|
													Effect.always(
														Ok({
															state: nextState,
															out: {
																status: "success",
																replyText: reply,
																reminderScheduled: False,
															},
														}),
													),
											)
										},
									),
							),
					)
				}
			},
		)
	}
)
}

handleTriggerReminder : AgentState, Str -> Effect.Effect(Result({ state : AgentState, out : Str }, Str))
handleTriggerReminder = |state, reminderId|
	Effect.and_then(
		now,
		|nowMillis| {
			targetReminderRes = findReminderById(state.activeReminders, reminderId)

			match targetReminderRes {
				Err(err) => Effect.always(Err(err))
				Ok(rem) => {
					totalSteps = List.len(rem.milestones)
					milestoneRes = getMilestoneAtStep(rem.milestones, rem.currentStep)

					noticeText =
						match milestoneRes {
							Ok(m) => formatMilestoneNotice(rem.title, m.offsetMinutes)
							Err(_) => "⏰ Reminder alert for ${rem.title}"
						}

					nextStep = rem.currentStep + 1.U64
					isFinished = nextStep >= totalSteps

					updatedReminders =
						List.map(
							state.activeReminders,
							|r|
								if r.id == reminderId {
									{
										..r,
										currentStep: nextStep,
										status: if isFinished { "completed" } else { "active" },
									}
								} else {
									r
								},
						)

					nextState = { ..state, activeReminders: updatedReminders }
					updatedAgenda = formatAgendaMarkdown(updatedReminders, state.inbox)
					updatedIndex = buildIndexJson(state.inbox, updatedReminders, state.entities, nowMillis)

					if !isFinished {
						nextMilestoneRes = getMilestoneAtStep(rem.milestones, nextStep)

						nextDelay =
							match nextMilestoneRes {
								Ok(m) =>
									if m.triggerTimeMillis > nowMillis {
										m.triggerTimeMillis - nowMillis
									} else {
										1000.U64
									}
								Err(_) => 60000.U64
							}

						Effect.and_then(
							workerId,
							|selfId|
								Effect.and_then(
									rpcSchedule(selfId, triggerReminderMethod, reminderId, nextDelay),
									|_|
										Effect.and_then(
											writeFile("wiki_agenda.md", updatedAgenda),
											|_|
												Effect.and_then(
													writeFile("wiki_index.json", updatedIndex),
													|_|
														Effect.and_then(
															writeFile("wiki_index.json", updatedIndex),
															|_|
																Effect.and_then(
																	dispatchTelegramAlert(nextState, noticeText),
																	|_|
																		Effect.always(
																			Ok({
																				state: nextState,
																				out: noticeText,
																			}),
																		),
																),
														),
												),
										),
								),
						)
					} else {
						Effect.and_then(
							writeFile("wiki_agenda.md", updatedAgenda),
							|_|
								Effect.and_then(
									writeFile("wiki_index.json", updatedIndex),
									|_| {
										finalMsg = "Final reminder completed: ${noticeText}"
										Effect.and_then(
											dispatchTelegramAlert(nextState, finalMsg),
											|_|
												Effect.always(
													Ok({
														state: nextState,
														out: finalMsg,
													}),
												),
										)
									},
								),
						)
					}
				}
			}
		},
	)

handleMidnightOrganizer : AgentState, Str -> Effect.Effect(Result({ state : AgentState, out : Str }, Str))
handleMidnightOrganizer = |state, _payload|
	Effect.and_then(
		now,
		|nowMillis| {
			archivedInbox =
				List.map(state.inbox, |item| { ..item, status: "organized" })

			agendaContent = formatAgendaMarkdown(state.activeReminders, archivedInbox)
			nextIndexJson = buildIndexJson(archivedInbox, state.activeReminders, state.entities, nowMillis)

			Effect.and_then(
				writeFile("wiki_agenda.md", agendaContent),
				|_|
					Effect.and_then(
						writeFile("wiki_index.json", nextIndexJson),
						|_| {
							nextState = {
								..state,
								inbox: archivedInbox,
								lastProcessedTime: nowMillis,
							}
							Effect.always(
								Ok({
									state: nextState,
									out: "Midnight organization complete at ${Str.inspect(nowMillis)}. Inbox processed and agenda refreshed.",
								}),
							)
						},
					),
			)
		},
	)

handleQueryAgenda : AgentState, Str -> Result(Str, Str)
handleQueryAgenda = |state, _query|
	Ok(formatAgendaMarkdown(state.activeReminders, state.inbox))

agent : Agent(AgentState)
agent =
	define(
		{
			name: "reminders-assistant",
			version: "0.1.0",
			description: "Durable personal reminders assistant with LLM Wiki storage and exponential reminders.",
		},
		initAgent,
		serializeState,
		deserializeState,
	)
		|> registerEffectfulTyped(
			processMessageMethod,
			handleProcessMessage,
			decodeMessageInput,
			encodeMessageOutput,
		)
		|> registerEffectfulTyped(
			triggerReminderMethod,
			handleTriggerReminder,
			|s| Ok(s),
			|s| s,
		)
		|> registerEffectfulTyped(
			midnightOrganizerMethod,
			handleMidnightOrganizer,
			|s| Ok(s),
			|s| s,
		)
		|> registerReadOnlyTyped(
			queryAgendaMethod,
			handleQueryAgenda,
			|s| Ok(s),
			|s| s,
		)
		|> withHttpMount({
			pathPrefix: "/telegram/{id}",
			corsOrigins: ["*"],
			webhookSuffix: "webhook",
		})
		|> build
