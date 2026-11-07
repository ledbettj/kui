# QuestBros

See which of your friends have done, or are on, a quest, even while they're
offline.

Each row of the quest log list shows four numbers: friends who have completed
the quest, haven't, are on it, and those you've no data for yet. Hover them for
the names. Open a quest in your log or at a quest giver and a small panel lists
each friend too:

```
Alice: on it (3/8)
Bob: done (as of 2d ago)
Carol: not done
```

Everyone in the group needs the addon, and each of you needs the others on
your WoW friends list, including any alts you want to see.

## How it works

Addons can't reach an offline player, so each copy saves what it learns and
passes it on. If you and Alice are never online together but you both overlap
with Bob, Bob carries her quests to you. A row older than an hour says how old
it is, and "not done" only means not done as of then.

Your own alts appear too, updated whenever you log in on them.

## Commands

- `/qb`: who you're connected to, and what's known about each character
- `/qb sync`: ask online friends for updates now

## Testing

`lua5.1 test/sim.lua`, from this folder, runs several simulated clients
against each other with no game needed.
