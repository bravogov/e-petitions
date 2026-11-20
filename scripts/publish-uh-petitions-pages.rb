# frozen_string_literal: true

# Publish the five source-controlled informational products through the
# original native Rails Page system, retaining normal admin editing.
# Never silently overwrite any later parliamentary editorial work.
root = ENV.fetch("PETITIONS_PUBLIC_CONTENT_ROOT", Rails.root.to_s)
pages = %w[help standards cookies privacy accessibility]
raise "Unexpected page set" unless pages.size == 5
raise "Petitions intake not closed" unless Site.disable_petition_creation? && Site.disable_collecting_signatures?

drafts = pages.map do |slug|
  text = File.read(File.join(root, "content/petitions/#{slug}.md"), encoding: "UTF-8")
  title = text.lines.first.sub(/\A# /, "").strip
  raise "Invalid title: #{slug}" unless text.start_with?("# ") && title.size.between?(5, 95)
  raise "Insufficient substantive content: #{slug}" unless text.size >= 500
  raise "UK response/debate thresholds are not authorised" if text.match?(/\b(?:10,000|100,000)\b/)
  [slug, title, text]
end

Page.transaction do
  drafts.each do |slug, title, text|
    existing = Page.find_by(slug: slug)
    if existing
      raise "Existing editorial page must not be overwritten: #{slug}" unless
        existing.title == title && existing.content == text && existing.enabled? && !existing.redirect?
      puts "UNCHANGED #{slug}"
      next
    end
    page = Page.create!(slug: slug, title: title, content: text, enabled: true,
                        redirect: false, disable_toc: false)
    puts "PUBLISHED #{slug} page_id=#{page.id}"
  end
end
puts "NATIVE_PAGES=#{Page.where(slug: pages, enabled: true).count}"
