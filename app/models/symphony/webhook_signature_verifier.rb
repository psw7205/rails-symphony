module Symphony
  class WebhookSignatureVerifier
    LINEAR_MAX_AGE_MS = 60_000

    def self.verify(provider:, raw_body:, signature:, secret:, payload: nil, now: Time.current)
      return missing_signature if signature.blank?
      return invalid_signature("missing_secret") if secret.blank?

      case provider.to_s
      when "github"
        verify_github(raw_body: raw_body, signature: signature, secret: secret)
      when "linear"
        verify_linear(raw_body: raw_body, signature: signature, secret: secret, payload: payload, now: now)
      else
        invalid_signature("unsupported_provider")
      end
    end

    class << self
      private
        def verify_github(raw_body:, signature:, secret:)
          expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)}"
          compare_signatures(expected, signature)
        end

        def verify_linear(raw_body:, signature:, secret:, payload:, now:)
          expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
          result = compare_signatures(expected, signature)
          return result unless result[:ok]

          timestamp = payload.to_h["webhookTimestamp"].to_i
          now_ms = (now.to_f * 1000).to_i
          return invalid_signature("invalid_timestamp") if timestamp <= 0
          return invalid_signature("stale_timestamp") if (now_ms - timestamp).abs > LINEAR_MAX_AGE_MS

          verified_signature
        end

        def compare_signatures(expected, actual)
          return invalid_signature("signature_mismatch") unless expected.bytesize == actual.to_s.bytesize
          return invalid_signature("signature_mismatch") unless ActiveSupport::SecurityUtils.secure_compare(expected, actual.to_s)

          verified_signature
        end

        def verified_signature
          { ok: true, signature_state: "verified" }
        end

        def missing_signature
          { ok: false, signature_state: "missing", error: "missing_signature" }
        end

        def invalid_signature(error)
          { ok: false, signature_state: "invalid", error: error }
        end
    end
  end
end
