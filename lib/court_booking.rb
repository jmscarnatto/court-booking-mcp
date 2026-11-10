require "date"
require "securerandom"

module CourtBooking
  class Error < StandardError; end

  Club = Struct.new(:id, :name, :city, :sports, keyword_init: true)
  Court = Struct.new(:id, :club_id, :name, :sport, :price_usd, keyword_init: true)
  Booking = Struct.new(:id, :court_id, :date, :start_time, :player_name, keyword_init: true)

  SPORTS = ["padel", "pickleball", "tennis"].freeze
  START_TIMES = (8..21).map { |hour| format("%02d:00", hour) }.freeze

  CLUBS = [
    Club.new(id: "club_palm", name: "Palm Court Padel Club", city: "Miami", sports: ["padel", "pickleball"]),
    Club.new(id: "club_bay", name: "Bayfront Tennis Center", city: "Miami", sports: ["tennis", "padel"]),
    Club.new(id: "club_lake", name: "Lakeside Pickleball", city: "Austin", sports: ["pickleball"]),
  ].freeze

  COURTS = [
    Court.new(id: "court_palm_1", club_id: "club_palm", name: "Padel 1", sport: "padel", price_usd: 40),
    Court.new(id: "court_palm_2", club_id: "club_palm", name: "Padel 2", sport: "padel", price_usd: 40),
    Court.new(id: "court_palm_3", club_id: "club_palm", name: "Pickleball 1", sport: "pickleball", price_usd: 24),
    Court.new(id: "court_bay_1", club_id: "club_bay", name: "Clay 1", sport: "tennis", price_usd: 32),
    Court.new(id: "court_bay_2", club_id: "club_bay", name: "Padel Center", sport: "padel", price_usd: 44),
    Court.new(id: "court_lake_1", club_id: "club_lake", name: "Court A", sport: "pickleball", price_usd: 20),
    Court.new(id: "court_lake_2", club_id: "club_lake", name: "Court B", sport: "pickleball", price_usd: 20),
  ].freeze

  class Store
    def initialize(today: -> { Date.today })
      @today = today
      @bookings = {}
      @requests = {}
    end

    def search_clubs(city: nil, sport: nil)
      CLUBS.select do |club|
        (city.nil? || club.city.casecmp?(city)) && (sport.nil? || club.sports.include?(sport))
      end
    end

    def available_slots(club_id:, date:, sport: nil)
      club = CLUBS.find { |item| item.id == club_id } || raise(Error, "Unknown club_id #{club_id}. Call search_clubs to get valid ids.")
      day = parse_date(date)
      courts = COURTS.select { |court| court.club_id == club.id && (sport.nil? || court.sport == sport) }
      courts.map do |court|
        {
          court_id: court.id,
          court_name: court.name,
          sport: court.sport,
          price_usd: court.price_usd,
          duration_minutes: 60,
          available_start_times: START_TIMES.reject { |start_time| taken?(court, day, start_time) },
        }
      end
    end

    def book(court_id:, date:, start_time:, player_name:, idempotency_key:)
      request = [court_id, date, start_time, player_name]
      previous = @requests[idempotency_key]
      if previous
        return previous[:booking] if previous[:request] == request

        raise Error, "idempotency_key #{idempotency_key} was already used with different arguments. Use a new key for a new booking."
      end

      court = COURTS.find { |item| item.id == court_id } || raise(Error, "Unknown court_id #{court_id}. Call list_available_slots to get valid ids.")
      day = parse_date(date)
      raise Error, "start_time must be a full hour from 08:00 to 21:00." unless START_TIMES.include?(start_time)
      raise Error, "#{court.name} is taken on #{day} at #{start_time}. Call list_available_slots to see free times." if taken?(court, day, start_time)

      booking = Booking.new(id: "bk_#{SecureRandom.hex(4)}", court_id: court.id, date: day.iso8601, start_time: start_time, player_name: player_name)
      @bookings[[court.id, day, start_time]] = booking
      @requests[idempotency_key] = { request: request, booking: booking }
      booking
    end

    private

    def parse_date(value)
      day = Date.strptime(value, "%Y-%m-%d")
      raise Error, "date #{value} is in the past." if day < @today.call

      day
    rescue Date::Error
      raise Error, "date must use the format YYYY-MM-DD."
    end

    def taken?(court, day, start_time)
      @bookings.key?([court.id, day, start_time]) || seeded_booking?(court, day, start_time)
    end

    def seeded_booking?(court, day, start_time)
      ((COURTS.index(court) + day.yday + start_time.to_i) % 4).zero?
    end
  end
end
