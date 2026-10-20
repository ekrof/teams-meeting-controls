#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Teams: Like
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 👍
# @raycast.packageName Teams Reactions
# @raycast.description Teams meeting: like (accessibility, any window size)

"${0:A:h}/lib/run-teams-ui.sh" like
