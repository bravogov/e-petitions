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

  it 'returns visitors to the independent United Hampshire Parliament website' do
    template = views.join('application/_header.html.erb').read
    expect(template).to include('https://parliament.uhrblx.com/')
    expect(template).not_to include('https://www.parliament.uk')
  end
end
