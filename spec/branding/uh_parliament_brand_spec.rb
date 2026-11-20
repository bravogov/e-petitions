require 'rails_helper'
require 'digest'

RSpec.describe 'United Hampshire Parliament identity' do
  let(:views) { Rails.root.join('app', 'views') }
  let(:logo_path) { Rails.root.join('public', 'uh-parliament-brand', 'uh-parliament-logo.png') }
  let(:expected_digest) { 'ab4fc9c480ce922746db6fe5f5a0d5792d5fdd3228e548ab0ea80c43b7df237b' }

  it 'preserves the exact approved parliamentary header image' do
    expect(Digest::SHA256.file(logo_path).hexdigest).to eq(expected_digest)
  end

  it 'uses the UH Parliament image in both public and editorial footers' do
    %w[application/_footer.html.erb layouts/editor.html.erb].each do |file|
      template = views.join(file).read
      expect(template).to include('/uh-parliament-brand/uh-parliament-logo.png')
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

  it 'serves original PC-approved icon assets to public and moderation users' do
    {
      'favicon.ico' => '4164ad861c980afdbcdde5695359fb3ab36fbfa4b29bf7f40aa53da7f32d2f67',
      'favicon-admin.ico' => '4164ad861c980afdbcdde5695359fb3ab36fbfa4b29bf7f40aa53da7f32d2f67',
      'apple-touch-icon.png' => '5707bb43de15c791446853370bf415aa66d4a7e4881070e0a386ec1bab317a9c',
      'uh-parliament-brand/uh-parliament-icon.png' => '5707bb43de15c791446853370bf415aa66d4a7e4881070e0a386ec1bab317a9c'
    }.each do |file, digest|
      expect(Digest::SHA256.file(Rails.root.join('public', file)).hexdigest).to eq(digest)
    end
  end

  it 'removes the original UK crown and portcullis graphic from native public and editorial banners' do
    %w[application/_header.html.erb layouts/editor.html.erb].each do |file|
      template = views.join(file).read
      banner = template.match(/<a href="\/" class="banner-logo"[^>]*>(.*?)<\/a>/m)
      expect(banner).not_to be_nil
      expect(banner[1]).to include('src="/uh-parliament-brand/uh-parliament-logo.png"')
      expect(banner[1]).to include('>Petitions</span>')
      expect(banner[1]).not_to include('<svg')
    end
  end

  it 'uses only the controlled ICO favicon in the native site layouts' do
    %w[application/_os.html.erb layouts/editor.html.erb].each do |file|
      template = views.join(file).read
      expect(template).to include('href="/favicon.ico"')
      expect(template).not_to include('href="/favicon.svg"')
    end
  end

  it 'returns visitors to the independent United Hampshire Parliament website' do
    template = views.join('application/_header.html.erb').read
    expect(template).to include('https://parliament.uhrblx.com/')
    expect(template).not_to include('https://www.parliament.uk')
  end
end
