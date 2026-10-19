# File generated from Twilio's OpenAPI spec — do not edit manually
defmodule Twilio.Resources.Api.V2010.ValidationRequest do
  @moduledoc """
  The answer of `CreateValidationRequest`.

  Parent: `/Accounts/{Sid}.json`

  ## Properties

  | Field | Description |
  |-------|-------------|
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  | `account_sid` | The SID of the [Account](https://www.twilio.com/docs/iam/api/account) responsible for the Caller ID. |
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  | `call_sid` | The SID of the [Call](https://www.twilio.com/docs/voice/api/call-resource) the Caller ID is associated with. |
  | `friendly_name` | The string that you assigned to describe the resource.. PII: standard |
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  | `phone_number` | The phone number to verify in [E.164](https://www.twilio.com/docs/glossary/what-e164) format, which consists of a + followed by the country code and subscriber number.. Format: phone-number. PII: standard |
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  | `validation_code` | The 6 digit validation code that someone must enter to validate the Caller ID  when `phone_number` is called. |
  """

  @type t :: %__MODULE__{
          account_sid: String.t() | nil,
          call_sid: String.t() | nil,
          friendly_name: String.t() | nil,
          phone_number: String.t() | nil,
          validation_code: String.t() | nil
        }

  defstruct [:account_sid, :call_sid, :friendly_name, :phone_number, :validation_code]

  @object_name "api.v2010.account.validation_request"
  def object_name, do: @object_name
end
