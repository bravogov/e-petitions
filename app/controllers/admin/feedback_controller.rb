# frozen_string_literal: true

# Existing Parliament MFA/session administration protects this internal inbox.
# Feedback never becomes a petition or a public parliamentary publication.
class Admin::FeedbackController < Admin::AdminController
  before_action :require_sysadmin
  before_action :find_feedback, only: %i[show update]

  def index
    @state = params[:state].presence
    @state = nil unless Feedback::HANDLING_STATUSES.include?(@state)
    scope = Feedback.order(id: :desc)
    scope = scope.where(handling_status: @state) if @state
    @feedbacks = scope.paginate(page: params[:page], per_page: 25)
    @counts = Feedback.group(:handling_status).count
  end

  def show
    @events = @feedback.handling_events.order(created_at: :desc)
  end

  def update
    attrs = feedback_params
    status = attrs[:handling_status]
    unless Feedback::HANDLING_STATUSES.include?(status)
      @feedback.errors.add(:handling_status, "is not a recognised handling state")
      @events = @feedback.handling_events.order(created_at: :desc)
      return render :show, status: :unprocessable_entity
    end

    old_status = @feedback.handling_status
    new_note = attrs[:handling_note].to_s.strip
    if old_status == status && @feedback.handling_note.to_s == new_note
      return redirect_to admin_feedback_entry_path(@feedback),
        notice: "No changes to record"
    end

    Feedback.transaction do
      @feedback.update!(
        handling_status: status,
        handling_note: new_note,
        handled_by: current_user,
        handled_at: Time.current
      )
      FeedbackHandlingEvent.create!(
        feedback: @feedback, admin_user: current_user,
        from_status: old_status, to_status: status, note: new_note
      )
    end
    redirect_to admin_feedback_entry_path(@feedback),
      notice: "Feedback handling record updated"
  rescue ActiveRecord::RecordInvalid
    @events = @feedback.handling_events.order(created_at: :desc)
    render :show, status: :unprocessable_entity
  end

  private

  def find_feedback
    @feedback = Feedback.find(params[:id])
  end

  def feedback_params
    params.require(:feedback).permit(:handling_status, :handling_note)
  end
end
