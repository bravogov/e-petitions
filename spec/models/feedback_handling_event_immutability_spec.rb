# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedbackHandlingEvent do
  it "validates actual casework states" do
    event = described_class.new(from_status: "unknown", to_status: "closed")
    event.valid?
    expect(event.errors[:from_status]).not_to be_empty
  end

  it "rejects modification and deletion of previously recorded actions" do
    event = described_class.new
    expect { event.send(:reject_historical_mutation) }.
      to raise_error(ActiveRecord::ReadOnlyError, /permanent records/)
  end
end