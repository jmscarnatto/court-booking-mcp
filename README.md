# court-booking-mcp

A small MCP server that lets an AI agent find and book a padel, pickleball or tennis court.

https://github.com/user-attachments/assets/5f8b9712-ae40-499e-800a-85b9086bc5ed

It runs on mock data kept in memory. It is a demo of how a booking platform could expose its product to AI agents, not a client for a real API.

## Tools

| Tool | What it does |
| --- | --- |
| `search_clubs` | Finds clubs by city and sport. |
| `list_available_slots` | Lists the free one-hour slots of each court in a club on one date. |
| `book_court` | Books one court for one hour. |

## Design decisions

- **Retries never book twice.** Agents retry when a call times out. `book_court` requires an `idempotency_key`: the same key returns the first booking, and the same key with different arguments is rejected.
- **Errors tell the agent what to do next.** A taken slot answers "Call list_available_slots to see free times" instead of a bare failure, so the agent can recover without the user.
- **Small responses.** Free slots are grouped by court as a list of start times, not one object per slot, to keep token use low.
- **Each tool returns the ids the next tool needs.** The agent never has to guess an id.
- **Honest annotations.** The two read tools are marked read-only; `book_court` is marked idempotent and not destructive, so clients can decide when to ask the user for confirmation.
- **Strict input.** JSON Schema validation with enums rejects bad arguments before any code runs.

## Run

Requires Ruby 3.x.

```sh
bundle install
bundle exec ruby test/court_booking_test.rb
```

Add it to Claude Code:

```sh
claude mcp add court-booking -- ruby /absolute/path/to/court-booking-mcp/server.rb
```

Or to any MCP client that uses a JSON config:

```json
{
  "mcpServers": {
    "court-booking": {
      "command": "ruby",
      "args": ["/absolute/path/to/court-booking-mcp/server.rb"]
    }
  }
}
```

Then ask: "Find a padel court in Miami tomorrow after 6 pm and book it for Ana."

## Limits

- Data is mock and lives in memory; bookings are lost when the server stops.
- No authentication, payments or cancellation.
- Transport is stdio only. The same server can run over Streamable HTTP inside a Rails app with the official SDK.

Built with the official [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk).
