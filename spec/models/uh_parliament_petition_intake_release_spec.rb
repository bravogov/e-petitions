require 'rails_helper'

RSpec.describe "UH parliamentary petition intake release gate", type: :model do
  let(:settings) do
    instance_double(Site, disable_petition_creation: false, disable_collecting_signatures: false)
  end

  before do
    allow(Site).to receive(:instance).and_return(settings)
    allow(Rails.env).to receive(:production?).and_return(true)
    allow(ENV).to receive(:fetch).and_call_original
  end

  def permit_deployment_release(value)
    allow(ENV).to receive(:fetch).
      with("UH_PETITIONS_SCHEME_RELEASED", "false").and_return(value)
  end

  it "keeps both public intake routes closed with no release permission" do
    permit_deployment_release("false")
    expect(Site.disable_petition_creation?).to be(true)
    expect(Site.signature_collection_disabled?).to be(true)
  end

  it "does not accept values other than the explicit true release setting" do
    permit_deployment_release("TRUE")
    expect(Site.disable_petition_creation?).to be(true)
    expect(Site.disable_collecting_signatures?).to be(true)
  end

  it "still honours the House-controlled site settings if release is permitted" do
    permit_deployment_release("true")
    expect(Site.disable_petition_creation?).to be(false)
    expect(Site.disable_collecting_signatures?).to be(false)
  end

  it "does not override a site-level stop even when release is permitted" do
    permit_deployment_release("true")
    allow(settings).to receive(:disable_petition_creation).and_return(true)
    allow(settings).to receive(:disable_collecting_signatures).and_return(true)
    expect(Site.disable_petition_creation?).to be(true)
    expect(Site.disable_collecting_signatures?).to be(true)
  end

  it "preserves existing test and development configuration behaviour" do
    permit_deployment_release("false")
    allow(Rails.env).to receive(:production?).and_return(false)
    expect(Site.disable_petition_creation?).to be(false)
    expect(Site.disable_collecting_signatures?).to be(false)
  end
end
