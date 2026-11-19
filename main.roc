app [agent] { pf: platform "https://github.com/thesparq/roc-golem/releases/download/v1.4.3/2GmoYXoEV7NScPfqt02Eom1X6FSt6j4dcMN447hZefw.tar.zst" }

import pf.Golem exposing [Agent]
import RemindersAgent
import Types exposing [AgentState]

State : AgentState

agent : Agent(State)
agent = RemindersAgent.agent
