# Adjust existing native site settings, preserving actual mailbox addresses.
site = Site.first or raise "Petitions site not found"
from = "Petitions: United Hampshire Government and Parliament"
replacement = "United Hampshire Parliamentary Petitions"
values = {}
[:email_from, :feedback_email].each do |field|
  old = site.public_send(field).to_s
  raise "Unexpected sender setting" unless old.include?(from)
  updated = old.sub(from, replacement)
  address = ->(value) { value[/<([^>]+)>/, 1] }
  raise "Sender/recipient email address would change" unless address.call(old) == address.call(updated)
  values[field] = updated
end
site.update!(values)
site.reload
values.each do |field, value|
  raise "Native site setting did not persist" unless site.public_send(field) == value
end
puts "EXISTING_PARLIAMENT_SENDER_IDENTITIES_CORRECTED_WITHOUT_ADDRESS_CHANGE"
