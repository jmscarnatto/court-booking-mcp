require "bundler/setup"
require "minitest/autorun"
require_relative "../lib/court_booking"

class CourtBookingTest < Minitest::Test
  DATE = "2030-01-15"

  def setup
    @store = CourtBooking::Store.new(today: -> { Date.new(2030, 1, 1) })
    court = @store.available_slots(club_id: "club_palm", date: DATE, sport: "padel").first
    @court_id = court[:court_id]
    @start_time = court[:available_start_times].first
  end

  def book(**overrides)
    @store.book(court_id: @court_id, date: DATE, start_time: @start_time, player_name: "Ana", idempotency_key: "key-0001", **overrides)
  end

  def free_times
    @store.available_slots(club_id: "club_palm", date: DATE).find { |court| court[:court_id] == @court_id }[:available_start_times]
  end

  def test_search_filters_by_city_and_sport
    assert_equal ["club_palm", "club_bay"], @store.search_clubs(city: "miami", sport: "padel").map(&:id)
    assert_empty @store.search_clubs(city: "Austin", sport: "tennis")
  end

  def test_booked_slot_is_no_longer_available
    book
    refute_includes free_times, @start_time
  end

  def test_same_slot_cannot_be_booked_twice
    book
    error = assert_raises(CourtBooking::Error) { book(idempotency_key: "key-0002") }
    assert_match(/is taken/, error.message)
  end

  def test_retry_with_same_key_returns_the_first_booking
    assert_equal book.id, book.id
  end

  def test_same_key_with_different_arguments_is_rejected
    book
    assert_raises(CourtBooking::Error) { book(player_name: "Luis") }
  end

  def test_rejects_invalid_input
    assert_raises(CourtBooking::Error) { book(date: "2029-12-31") }
    assert_raises(CourtBooking::Error) { book(date: "tomorrow") }
    assert_raises(CourtBooking::Error) { book(start_time: "18:30") }
    assert_raises(CourtBooking::Error) { book(court_id: "court_none") }
    assert_raises(CourtBooking::Error) { @store.available_slots(club_id: "club_none", date: DATE) }
  end
end
