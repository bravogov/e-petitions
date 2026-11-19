# frozen_string_literal: true

require "rails_helper"

RSpec.describe "United Hampshire parliamentary petitions source safety" do
  it "uses Parliament-owned native Rails defaults rather than UK services" do
    model = Rails.root.join("app/models/site.rb").read
    expect(model).to include("petition.parliament.uhrblx.com")
    expect(model).to include("moderate.petition.parliament.uhrblx.com")
    expect(model).to include("Petitions - United Hampshire Parliament")
    expect(model).not_to include("petition.parliament.uk")
    expect(model).not_to include("UK Government and Parliament")
  end

  it "retains UK procedural thresholds only as inactive inherited defaults" do
    site = Rails.root.join("app/models/site.rb").read
    expect(site).to include("def disable_petition_creation?")
    expect(site).to include("def disable_collecting_signatures?")
    # The House has not authorised opening the electronic petition scheme.
    # Existing production flags must remain closed; no numeric default is
    # accepted here as a UH rule or as an approval to reopen.
  end

  it "refuses to generate the obsolete UK 2022 privacy update in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    expect { PetitionMailer.privacy_policy_update_email(Object.new).message }.
      to raise_error(RuntimeError, /inherited 2022 privacy notice/)
    expect { EmailPrivacyPolicyUpdatesJob.new.perform(time: Time.current) }.
      to raise_error(RuntimeError, /Bulk delivery of the inherited 2022 privacy notice/)
  end
end
