require "rails_helper"

RSpec.describe EmailPrivacyPolicyUpdateJob, type: :job do
  describe "United Hampshire production safeguard" do
    it "does not generate privacy notification records or enqueue outgoing mail" do
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(PrivacyNotification).not_to receive(:create!)
      expect(DeliverPrivacyPolicyUpdateJob).not_to receive(:perform_later)
      expect {
        described_class.perform_now(petition: nil, time: Time.current)
      }.not_to change { PrivacyNotification.count }
    end
  end

  describe "perform" do
    context "signature validated, without matching privacy_notification" do
      let(:petition) { FactoryBot.create(:petition) }
      let(:time) { 1.year.ago }

      let!(:signature) do
        FactoryBot.create(:validated_signature, petition: petition)
      end

      let(:subject) do
        described_class.perform_now(petition: petition, time: time)
      end

      it "sends an email" do
        expect { subject }.to change { enqueued_jobs.count }.by(1)
      end

      it "creates a privacy_notification record" do
        expect { subject }.to change { PrivacyNotification.count }.by(1)
      end

      it "sets ignore_petitions_before on privacy_notification" do
        subject

        expect(PrivacyNotification.last.ignore_petitions_before)
          .to be_within(1.second)
          .of(time)
      end
    end

    (Signature::STATES - [Signature::VALIDATED_STATE]).each do |state|
      context "signature #{state}, without matching privacy_notification" do
        let(:petition) { FactoryBot.create(:petition) }

        let!(:signature) do
          FactoryBot.create("#{state}_signature", petition: petition)
        end

        it "does no send an email" do
          expect { subject }.not_to change { enqueued_jobs.count }
        end

        it "does not creates a privacy_notification record" do
          expect { subject }.not_to change { PrivacyNotification.count }
        end
      end
    end

    context "signature validated, with matching privacy_notification" do
      let(:petition) { FactoryBot.create(:petition) }

      let!(:signature) do
        FactoryBot.create(:validated_signature, petition: petition)
      end

      let!(:privacy_notification) do
        FactoryBot.create(:privacy_notification, id: signature.uuid)
      end

      it "does not send an email" do
        expect { subject }.not_to change { enqueued_jobs.count }
      end

      it "does not create a privacy_notification record" do
        expect { subject }.not_to change { PrivacyNotification.count }
      end
    end
  end
end
