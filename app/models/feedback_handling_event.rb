# frozen_string_literal: true

# An event records an officer's action as it happened. Corrections are new
# events, never replacements for the earlier event or its original attribution.
class FeedbackHandlingEvent < ActiveRecord::Base
  belongs_to :feedback
  belongs_to :admin_user

  validates :feedback, :admin_user, :from_status, :to_status, presence: true
  validates :from_status, :to_status, inclusion: { in: Feedback::HANDLING_STATUSES }
  validates :note, length: { maximum: 4000 }, allow_blank: true

  before_update :reject_historical_mutation
  before_destroy :reject_historical_mutation

  private

  def reject_historical_mutation
    raise ActiveRecord::ReadOnlyError,
      "Feedback handling events are permanent records; add a corrective event"
  end
end