# frozen_string_literal: true

# Native staff case-handling for enquiries received by the existing Rails
# Feedback transaction. Existing public submissions and email jobs are kept.
class AddPetitionsFeedbackHandling < ActiveRecord::Migration[8.0]
  def change
    add_column :feedback, :handling_status, :string, limit: 20,
      default: "new", null: false
    add_column :feedback, :handled_by_id, :bigint
    add_column :feedback, :handled_at, :datetime
    add_column :feedback, :handling_note, :text
    add_column :feedback, :updated_at, :datetime
    add_index :feedback, :handling_status
    add_foreign_key :feedback, :admin_users, column: :handled_by_id

    create_table :feedback_handling_events do |t|
      t.bigint :feedback_id, null: false
      t.bigint :admin_user_id, null: false
      t.string :from_status, limit: 20, null: false
      t.string :to_status, limit: 20, null: false
      t.text :note
      t.datetime :created_at, null: false
    end
    add_index :feedback_handling_events, [:feedback_id, :created_at],
      name: "index_feedback_handling_events_by_feedback_and_date"
    add_foreign_key :feedback_handling_events, :feedback, column: :feedback_id
    add_foreign_key :feedback_handling_events, :admin_users, column: :admin_user_id
  end
end
