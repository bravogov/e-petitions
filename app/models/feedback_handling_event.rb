# frozen_string_literal: true

class FeedbackHandlingEvent < ActiveRecord::Base
  belongs_to :feedback
  belongs_to :admin_user

  validates :feedback, :admin_user, :from_status, :to_status, presence: true
  validates :note, length: { maximum: 4000 }, allow_blank: true
end
