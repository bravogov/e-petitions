require 'mail'

class Feedback < ActiveRecord::Base
  HANDLING_STATUSES = %w[new reviewing closed].freeze

  belongs_to :handled_by, class_name: "AdminUser", optional: true
  has_many :handling_events, class_name: "FeedbackHandlingEvent",
    dependent: :restrict_with_exception

  validates :handling_status, inclusion: { in: HANDLING_STATUSES }
  validates :handling_note, length: { maximum: 4000 }, allow_blank: true
  validates :handling_note, presence: true, if: -> { handling_status == "closed" }
  class RateLimitExceededError < RuntimeError; end

  validates :comment, presence: true, length: { maximum: 32768 }
  validates :petition_link_or_title, length: { maximum: 255 }, allow_blank: true
  validates :email, email: true, length: { maximum: 255 }, allow_blank: true

  before_create do
    if rate_limit.exceeded?(self)
      raise RateLimitExceededError, "The rate limit for #{ip_address} has been exceeded"
    end
  end

  after_create do
    Appsignal.increment_counter("feedback.created", 1)
  end

  def petition_link?
    petition_link_or_title =~ /\A#{Regexp.escape(Site.url)}/
  end

  def rate(window = 5.minutes)
    time = created_at || Time.current
    period = Range.new(time - window, time)

    self.class.where(ip_address: ip_address, created_at: period).count
  end

  def domain
    Mail::Address.new(email).domain
  rescue Mail::Field::ParseError
    nil
  end

  private

  def rate_limit
    @rate_limit ||= RateLimit.first_or_create!
  end
end
