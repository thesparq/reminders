module [
	standardOffsets,
	calculateLadder,
	formatMilestoneNotice,
	parseReminderIntent,
]

import Types exposing [Result, ReminderMilestone]

standardOffsets : List(U64)
standardOffsets = [30.U64, 20.U64, 10.U64, 5.U64, 2.U64, 1.U64, 0.U64]

calculateLadder : U64, U64 -> List(ReminderMilestone)
calculateLadder = |targetMillis, nowMillis|
	filterMilestones(standardOffsets, targetMillis, nowMillis)

filterMilestones : List(U64), U64, U64 -> List(ReminderMilestone)
filterMilestones = |offsets, targetMillis, nowMillis|
	match offsets {
		[] => []
		[first, .. as rest] => {
			offsetMillis = first * 60000.U64
			tail = filterMilestones(rest, targetMillis, nowMillis)
			if targetMillis >= offsetMillis and (targetMillis - offsetMillis) > nowMillis {
				List.prepend(tail, { offsetMinutes: first, triggerTimeMillis: targetMillis - offsetMillis })
			} else {
				tail
			}
		}
	}

formatMilestoneNotice : Str, U64 -> Str
formatMilestoneNotice = |title, offsetMinutes|
	if offsetMinutes == 0.U64 {
		"⏰ *REMINDER:* ${title}\nIt is time right now!"
	} else if offsetMinutes == 1.U64 {
		"🔔 *Final Notice:* ${title} begins in 1 minute!"
	} else {
		"🔔 *Upcoming Reminder:* ${title} in ${Str.inspect(offsetMinutes)} minutes."
	}

parseReminderIntent : Str, U64 -> Result({ isReminder : Bool, title : Str, targetMillis : U64 }, Str)
parseReminderIntent = |rawText, nowMillis| {
	trimmed = Str.trim(rawText)
	lower = trimmed
	if Str.starts_with(lower, "remind me") or Str.starts_with(lower, "reminder:") or Str.starts_with(lower, "Remind me") {
		defaultDelay = 35.U64 * 60000.U64
		target = nowMillis + defaultDelay
		Ok({
			isReminder: True,
			title: trimmed,
			targetMillis: target,
		})
	} else {
		Ok({
			isReminder: False,
			title: trimmed,
			targetMillis: 0.U64,
		})
	}
}
