#!/usr/bin/env ruby
# frozen_string_literal: true
# Native repository check: source-based parliamentary brand, external links
# and truthful public contact routes. No external identity, data or network needed.
require "digest"
root = File.expand_path("..", __dir__)
views = File.join(root, "app", "views")
files = %w[
  pages/home/_pending.html.erb
  pages/home/_dissolved.html.erb
  pages/home/_dissolution_announced.html.erb
  feedback/new.html.erb
  signatures/signed.html.erb
  petitions/start.html.erb
  petitions/create/_action_stage.html.erb
  petitions/create/_background_stage.html.erb
  petitions/create/_check_and_submit_stage.html.erb
  petitions/events/_debate_scheduled.html.erb
  petitions/events/_parliament_debated_pending_outcome.html.erb
  admin/editor/show.html.erb
  admin/admin/index.html.erb
  admin/shared/_header.html.erb
  application/_footer.html.erb
  layouts/editor.html.erb
  petition_mailer/notify_creator_of_closing_date_change.html.erb
  petition_mailer/notify_creator_of_closing_date_change.text.erb
  petition_mailer/notify_signer_of_closing_date_change.html.erb
  petition_mailer/notify_signer_of_closing_date_change.text.erb
]
bad = /
  (?:https?:\/\/(?:www\.)?parliament\.uk(?:\/|\b)) |
  (?:https?:\/\/www\.gov\.uk\/register-to-vote) |
  (?:https?:\/\/www\.youtube\.com\/UKParliament) |
  (?:https?:\/\/www\.nationalarchives\.gov\.uk\/doc\/open-government-licence) |
  (?:petitionscommittee\@parliament\.uk) |
  (?:\@HoCPetitions) |
  (?:UK\s+Government) |
  (?:UK\s+Parliament)
  /x
failures = []
files.each do |rel|
  f = File.join(views, rel)
  content = File.read(f)
  failures << "#{rel}: inherited UK identity, contact or endpoint" if content.match?(bad)
end
checks = {
  "Parliament public information" => File.read(File.join(views,"pages/home/_pending.html.erb")).include?("https://parliament.uhrblx.com/"),
  "electoral registration guidance" => File.read(File.join(views,"signatures/signed.html.erb")).include?("https://www.gov.uhrblx.com/register-to-vote"),
  "parliamentary contact route" => File.read(File.join(views,"feedback/new.html.erb")).include?("https://parliament.uhrblx.com/contact/"),
  "official OGL endpoint" => %w[application/_footer.html.erb layouts/editor.html.erb].all? do |rel|
    File.read(File.join(views,rel)).include?("https://nationalarchives.gov.uhrblx.com/doc/open-government-licence/version/3/")
  end,
  "admin hub approved mark" => %w[admin/admin/index.html.erb admin/shared/_header.html.erb].all? do |rel|
    File.read(File.join(views,rel)).include?("/uh-parliament-brand/uh-parliament-icon.png")
  end,
  "admin hub no UK crest graphics" => %w[admin/admin/index.html.erb admin/shared/_header.html.erb].all? do |rel|
    !File.read(File.join(views,rel)).match?(/graphic-(?:portcullis|crest)/)
  end,
  "original Parliament binary" => Digest::SHA256.file(File.join(root,"public/uh-parliament-brand/uh-parliament-logo.png")).hexdigest ==
    "ab4fc9c480ce922746db6fe5f5a0d5792d5fdd3228e548ab0ea80c43b7df237b",
  "original Parliament icon binary" => Digest::SHA256.file(File.join(root,"public/uh-parliament-brand/uh-parliament-icon.png")).hexdigest ==
    "5707bb43de15c791446853370bf415aa66d4a7e4881070e0a386ec1bab317a9c"
}
routes = File.read(File.join(root, "config", "routes.rb"))
redirects = File.read(File.join(root, "app", "controllers", "redirects_controller.rb"))
checks["native Parliament direct route"] = routes.include?('"https://parliament.uhrblx.com/"') &&
  !routes.include?('"https://www.parliament.uk/"')
checks["native National Archives direct route"] = routes.include?('"https://nationalarchives.gov.uhrblx.com/doc/open-government-licence/version/3/"') &&
  !routes.include?("www.nationalarchives.gov.uk/information-management/our-services/crown-copyright.htm")
checks["legacy copyright route is not permanently cached"] =
  redirects.match?(/def national_archives\s+response\.headers\["Cache-Control"\] = "no-store"\s+redirect_to national_archives_url, status: :found/m) &&
  !redirects.match?(/def national_archives\s+http_cache_forever/m)
checks.each { |k,pass| failures << "Missing required #{k}" unless pass }
if failures.any?
  warn failures.join("\n")
  exit 1
end
puts "VERIFIED #{files.size} original Rails templates, #{checks.size} source invariants"
puts "Outstanding publication gate: historic privacy-policy mailer and House-approved service notices require institutional replacement."
