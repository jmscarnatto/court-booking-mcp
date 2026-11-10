ENV["BUNDLE_GEMFILE"] ||= File.expand_path("Gemfile", __dir__)
require "bundler/setup"
require "json"
require "mcp"
require_relative "lib/court_booking"

module Tools
  def self.respond(server_context)
    data = yield(server_context[:store])
    MCP::Tool::Response.new([{ type: "text", text: JSON.generate(data) }], structured_content: data)
  rescue CourtBooking::Error => e
    MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
  end

  class SearchClubs < MCP::Tool
    tool_name "search_clubs"
    description "Find racquet sports clubs. Filter by city and sport. Returns club ids to use with list_available_slots."
    input_schema(
      properties: {
        city: { type: "string", description: "City name, for example Miami" },
        sport: { type: "string", enum: CourtBooking::SPORTS },
      },
    )
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(server_context:, city: nil, sport: nil)
      Tools.respond(server_context) do |store|
        { clubs: store.search_clubs(city: city, sport: sport).map(&:to_h) }
      end
    end
  end

  class ListAvailableSlots < MCP::Tool
    tool_name "list_available_slots"
    description "List the free one-hour slots of each court in a club on one date. Returns court ids to use with book_court."
    input_schema(
      properties: {
        club_id: { type: "string" },
        date: { type: "string", description: "YYYY-MM-DD, today or later" },
        sport: { type: "string", enum: CourtBooking::SPORTS },
      },
      required: ["club_id", "date"],
    )
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(club_id:, date:, server_context:, sport: nil)
      Tools.respond(server_context) do |store|
        { club_id: club_id, date: date, courts: store.available_slots(club_id: club_id, date: date, sport: sport) }
      end
    end
  end

  class BookCourt < MCP::Tool
    tool_name "book_court"
    description "Book one court for one hour. Safe to retry: a repeated call with the same idempotency_key returns the first booking and never books twice."
    input_schema(
      properties: {
        court_id: { type: "string" },
        date: { type: "string", description: "YYYY-MM-DD, today or later" },
        start_time: { type: "string", description: "Full hour in 24-hour format, for example 18:00" },
        player_name: { type: "string", minLength: 1 },
        idempotency_key: { type: "string", minLength: 8, description: "Unique value created by the client for this booking. Send the same value when you retry." },
      },
      required: ["court_id", "date", "start_time", "player_name", "idempotency_key"],
    )
    annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

    def self.call(court_id:, date:, start_time:, player_name:, idempotency_key:, server_context:)
      Tools.respond(server_context) do |store|
        store.book(court_id: court_id, date: date, start_time: start_time, player_name: player_name, idempotency_key: idempotency_key).to_h
      end
    end
  end
end

server = MCP::Server.new(
  name: "court-booking",
  version: "0.1.0",
  instructions: "Demo server with mock data. Flow: search_clubs, then list_available_slots, then book_court.",
  tools: [Tools::SearchClubs, Tools::ListAvailableSlots, Tools::BookCourt],
  server_context: { store: CourtBooking::Store.new },
)

MCP::Server::Transports::StdioTransport.new(server).open
