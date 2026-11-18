app [agent] { pf: platform "https://github.com/thesparq/roc-golem/releases/download/v1.4.2/sCMpPilBt65rdAVsPINB5xqG7FtlRnTGj6Vj61B6ulE.tar.zst" }

import pf.Golem exposing [Agent]
import RemindersAgent
import Types exposing [AgentState]

State : AgentState

agent : Agent(State)
agent = RemindersAgent.agent
