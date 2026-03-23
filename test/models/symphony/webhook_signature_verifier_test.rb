require "test_helper"
require "openssl"

class Symphony::WebhookSignatureVerifierTest < ActiveSupport::TestCase
  test "verifies GitHub sha256 signatures" do
    payload = github_payload
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "github-secret", payload)}"

    result = Symphony::WebhookSignatureVerifier.verify(
      provider: "github",
      raw_body: payload,
      signature: signature,
      secret: "github-secret"
    )

    assert_equal true, result[:ok]
    assert_equal "verified", result[:signature_state]
  end

  test "rejects invalid GitHub signatures" do
    result = Symphony::WebhookSignatureVerifier.verify(
      provider: "github",
      raw_body: github_payload,
      signature: "sha256=deadbeef",
      secret: "github-secret"
    )

    assert_equal false, result[:ok]
    assert_equal "invalid", result[:signature_state]
  end

  test "verifies Linear signatures and recent timestamps" do
    payload = linear_payload(timestamp_ms: 4_102_444_800_000)
    signature = OpenSSL::HMAC.hexdigest("SHA256", "linear-secret", payload)

    result = Symphony::WebhookSignatureVerifier.verify(
      provider: "linear",
      raw_body: payload,
      signature: signature,
      secret: "linear-secret",
      payload: JSON.parse(payload),
      now: Time.at(4_102_444_800)
    )

    assert_equal true, result[:ok]
    assert_equal "verified", result[:signature_state]
  end

  test "rejects missing signatures" do
    payload = linear_payload(timestamp_ms: 4_102_444_800_000)

    result = Symphony::WebhookSignatureVerifier.verify(
      provider: "linear",
      raw_body: payload,
      signature: nil,
      secret: "linear-secret",
      payload: JSON.parse(payload),
      now: Time.at(4_102_444_800)
    )

    assert_equal false, result[:ok]
    assert_equal "missing", result[:signature_state]
  end

  test "rejects stale Linear timestamps" do
    payload = linear_payload(timestamp_ms: 4_102_444_800_000)
    signature = OpenSSL::HMAC.hexdigest("SHA256", "linear-secret", payload)

    result = Symphony::WebhookSignatureVerifier.verify(
      provider: "linear",
      raw_body: payload,
      signature: signature,
      secret: "linear-secret",
      payload: JSON.parse(payload),
      now: Time.at(4_102_444_900)
    )

    assert_equal false, result[:ok]
    assert_equal "invalid", result[:signature_state]
  end

  private
    def github_payload
      Rails.root.join("test/fixtures/files/webhooks/github/issues_opened.json").read
    end

    def linear_payload(timestamp_ms:)
      JSON.parse(Rails.root.join("test/fixtures/files/webhooks/linear/issue_created.json").read)
        .merge("webhookTimestamp" => timestamp_ms)
        .to_json
    end
end
