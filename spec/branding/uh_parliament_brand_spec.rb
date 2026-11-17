require 'rails_helper'
require 'digest'

RSpec.describe 'United Hampshire Parliament identity' do
  let(:views) { Rails.root.join('app', 'views') }
  let(:logo_path) { Rails.root.join('app', 'assets', 'images', 'frontend', 'uh-parliament-logo.png') }
  let(:expected_digest) { 'ab4fc9c480ce922746db6fe5f5a0d5792d5fdd3228e548ab0ea80c43b7df237b' }

  it 'preserves the exact approved parliamentary header image' do
    expect(Digest::SHA256.file(logo_path).hexdigest).to eq(expected_digest)
  end

  it 'uses the UH Parliament image in both public and editorial footers' do
    %w[application/_footer.html.erb layouts/editor.html.erb].each do |file|
      template = views.join(file).read
      expect(template).to include('frontend/uh-parliament-logo.png')
      expect(template).not_to include('frontend/uk-parliament-logo.svg')
      expect(template).not_to include('frontend/uk-government-logo.svg')
    end
  end

  it 'does not retain UK institutional names in the public masthead or notification layouts' do
    %w[
      application/_header.html.erb
      layouts/editor.html.erb
      layouts/default_mail.html.erb
      layouts/default_mail.text.erb
    ].each do |file|
      text = views.join(file).read
      expect(text).not_to include('UK Parliament')
      expect(text).not_to include('UK Government')
    end
  end

  it 'sets the native page titles and social site identity to United Hampshire' do
    %w[metadata.en-GB.yml page_titles.en-GB.yml].each do |file|
      text = Rails.root.join('config', 'locales', file).read
      expect(text).to include('United Hampshire Parliament and Government')
      expect(text).not_to include('Petitions - UK Government and Parliament')
    end
  end

  it 'returns visitors to the independent United Hampshire Parliament website' do
    template = views.join('application/_header.html.erb').read
    expect(template).to include('https://parliament.uhrblx.com/')
    expect(template).not_to include('https://www.parliament.uk')
  end
end
