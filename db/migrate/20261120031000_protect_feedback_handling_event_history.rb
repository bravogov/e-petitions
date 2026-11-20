# frozen_string_literal: true

# Preserve the original officer, event date, states and note even if a
# later application path attempts to bypass model-level protections.
class ProtectFeedbackHandlingEventHistory < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE FUNCTION protect_feedback_handling_event_history()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'Feedback handling history is append-only; record a correction'
          USING ERRCODE = '55000';
      END;
      $$;
      CREATE TRIGGER feedback_handling_events_append_only
      BEFORE UPDATE OR DELETE ON feedback_handling_events
      FOR EACH ROW
      EXECUTE FUNCTION protect_feedback_handling_event_history();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS feedback_handling_events_append_only ON feedback_handling_events;
      DROP FUNCTION IF EXISTS protect_feedback_handling_event_history();
    SQL
  end
end