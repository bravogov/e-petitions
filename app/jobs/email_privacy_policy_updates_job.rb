class EmailPrivacyPolicyUpdatesJob < ApplicationJob
  queue_as :high_priority

  def perform(time:)
    if Rails.env.production?
      raise "Bulk delivery of the inherited 2022 privacy notice is disabled pending House approval"
    end
    Petition.moderated.where(created_at: time..).find_each do |petition|
      EmailPrivacyPolicyUpdateJob.perform_later(petition: petition, time: time)
    end
  end
end
