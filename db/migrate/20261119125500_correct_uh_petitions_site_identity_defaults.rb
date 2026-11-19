# frozen_string_literal: true

# Correct the persistent defaults for future Rails site records only. Existing
# petitions, membership, sender settings and procedural thresholds are not
# changed. Earlier migrations remain unaltered to preserve legislative history.
class CorrectUhPetitionsSiteIdentityDefaults < ActiveRecord::Migration[8.0]
  def change
    change_column_default :sites, :title,
      from: "Petition parliament", to: "Petitions - United Hampshire Parliament"
    change_column_default :sites, :email_from,
      from: '"Petitions: United Hampshire Government and Parliament" <no-reply@petition.parliament.uhrblx.com>',
      to: '"United Hampshire Parliamentary Petitions" <no-reply@petition.parliament.uhrblx.com>'
    change_column_default :sites, :feedback_email,
      from: '"Petitions: United Hampshire Government and Parliament" <petitionscommittee@parliament.uk>',
      to: '"United Hampshire Parliamentary Petitions" <petitionscommittee@parliament.uhrblx.com>'
  end
end
