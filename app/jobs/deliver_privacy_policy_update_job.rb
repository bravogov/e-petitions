class DeliverPrivacyPolicyUpdateJob < EmailJob
  queue_as :low_priority

  self.mailer = PetitionMailer
  self.email = :privacy_policy_update_email

  def perform(*args)
    if Rails.env.production?
      Rails.logger.warn("Legacy privacy notice delivery blocked pending parliamentary authorisation")
      return
    end

    super
  end
end
