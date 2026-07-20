defmodule Matwork.Platform do
  @moduledoc "Operational domain: the inbound-webhook ledger."
  use Ash.Domain, otp_app: :matwork

  resources do
    resource Matwork.Platform.WebhookEvent do
      define :record_webhook_event, action: :record, args: [:provider, :external_id, :payload]
      define :get_webhook_event, action: :read, get_by: [:id]
      define :mark_webhook_processed, action: :mark_processed
    end
  end
end
