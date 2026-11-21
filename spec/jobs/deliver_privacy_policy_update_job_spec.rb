require "rails_helper"

RSpec.describe DeliverPrivacyPolicyUpdateJob, type: :job do
  describe "United Hampshire production safeguard" do
    it "does not invoke the inherited, unapproved privacy policy email" do
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(PetitionMailer).not_to receive(:privacy_policy_update_email)
      described_class.perform_now(nil)
    end
  end

  describe "perform" do
    let(:signature) { FactoryBot.create(:signature) }

    let(:privacy_notification) do
      FactoryBot.create(:privacy_notification, signature: signature)
    end

    it "sends an email" do
      expect {
        described_class.perform_now(privacy_notification)
      }.to change {
        ActionMailer::Base.deliveries.count
      }.by(1)
    end
  end
end
